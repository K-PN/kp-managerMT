import Foundation
import Security
import SoNoCore

struct AIConnection: Codable, Sendable {
    var baseURL: URL
    var token: String
    var expiresAt: Date
}
enum AIKeychain {
    private static let service = "vn.sono.personal.ai-session"
    static func load() throws -> AIConnection? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: "session", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw LedgerError.unavailable("Không đọc được phiên AI từ Keychain.") }
        return try JSONDecoder().decode(AIConnection.self, from: data)
    }
    static func save(_ connection: AIConnection) throws {
        guard connection.baseURL.scheme == "https", connection.baseURL.host != nil,
              connection.baseURL.user == nil, connection.baseURL.password == nil,
              connection.baseURL.query == nil, connection.baseURL.fragment == nil,
              !connection.token.isEmpty, connection.token.count <= 4096,
              connection.token.range(of: #"^[A-Za-z0-9._~+/\-]+={0,2}$"#, options: .regularExpression) != nil,
              connection.expiresAt > Date(), connection.expiresAt <= Date().addingTimeInterval(3600) else {
            throw LedgerError.invalid("Cần URL HTTPS và mã phiên ngắn hạn, có hiệu lực tối đa 60 phút. Không dùng API key nhà cung cấp.")
        }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "session"]
        let attributes: [String: Any] = [kSecValueData as String: try JSONCoding.encode(connection), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; attributes.forEach { item[$0.key] = $0.value }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw LedgerError.unavailable("Không lưu được phiên AI.") }
        } else if status != errSecSuccess { throw LedgerError.unavailable("Không cập nhật được phiên AI.") }
    }
    static func clear() { SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary) }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

/// Calls only a paired proxy. No provider credential or customer database is accepted by this adapter.
actor OnlineAIClient {
    private struct ImageRequest: Encodable { var requestID: UUID; var imageBase64: String; var mediaType = "image/jpeg"; var locale = "vi-VN" }
    private struct AudioRequest: Encodable { var requestID: UUID; var audioBase64: String; var mediaType = "audio/mp4"; var locale = "vi-VN" }
    private struct TranscriptResponse: Decodable { var text: String }
    private struct Extraction: Decodable {
        struct Row: Decodable {
            var rawText: String; var customerName: String?; var date: String?
            var amountVND: Int64?; var kind: String?; var note: String?
            var quantity: Int64?; var unitPriceVND: Int64?; var warning: String?
        }
        var rows: [Row]
    }
    func handwriting(image: Data, attachmentID: UUID, consent: Bool) async throws -> [OCRRow] {
        guard consent else { throw LedgerError.consentRequired }
        guard image.count <= 8_000_000 else { throw LedgerError.invalid("Ảnh gửi online phải dưới 8 MB.") }
        let data = try await send(path: "handwriting", body: ImageRequest(requestID: UUID(), imageBase64: image.base64EncodedString()))
        let response = try JSONDecoder().decode(Extraction.self, from: data)
        guard response.rows.count <= 500 else { throw LedgerError.invalid("Quá nhiều dòng. Hãy chia nhỏ trang.") }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = VietnameseDate.calendar; formatter.timeZone = VietnameseDate.calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        return response.rows.map { row in
            let date = row.date.flatMap { formatter.date(from: $0) }
            let kind = row.kind.flatMap(TransactionKind.init(rawValue:))
            var warnings = ["Kết quả AI cần đối chiếu ảnh gốc."]
            if date == nil { warnings.append("Ngày còn thiếu hoặc sai.") }
            if kind == nil || kind == .reversal { warnings.append("Chưa rõ loại giao dịch.") }
            if let warning = row.warning { warnings.append(String(warning.prefix(1000))) }
            return OCRRow(attachmentID: attachmentID, rawText: String(row.rawText.prefix(4000)), customerName: String((row.customerName ?? "").prefix(200)),
                          amount: row.amountVND, kind: kind == .reversal ? .debt : kind ?? .debt, date: date ?? Date(), note: String((row.note ?? "").prefix(4000)), warning: warnings.joined(separator: " "), quantity: row.quantity, unitPrice: row.unitPriceVND)
        }
    }
    func transcribe(audio: Data, consent: Bool) async throws -> String {
        guard consent else { throw LedgerError.consentRequired }
        guard audio.count <= 8_000_000 else { throw LedgerError.invalid("Bản ghi âm vượt 8 MB.") }
        let data = try await send(path: "transcribe", body: AudioRequest(requestID: UUID(), audioBase64: audio.base64EncodedString()))
        let response = try JSONDecoder().decode(TranscriptResponse.self, from: data)
        guard response.text.count <= 20_000 else { throw LedgerError.invalid("Văn bản nhận dạng quá dài.") }
        return response.text
    }
    private func send<T: Encodable>(path: String, body: T) async throws -> Data {
        guard let connection = try AIKeychain.load(), connection.expiresAt > Date() else { throw LedgerError.unavailable("Chưa ghép nối proxy AI hoặc phiên đã hết hạn. Cấu hình trong Cài đặt; nhập thủ công vẫn dùng được.") }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 45; config.timeoutIntervalForResource = 60
        config.httpCookieStorage = nil; config.urlCache = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: connection.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("Bearer \(connection.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONCoding.encode(body)
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.mimeType == "application/json" else { throw LedgerError.unavailable("Proxy AI từ chối yêu cầu. Kiểm tra phiên, hạn mức hoặc thử lại thủ công.") }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 2_000_000 else { throw LedgerError.invalid("Phản hồi AI vượt giới hạn.") }
            data.append(byte)
        }
        return data
    }
}
