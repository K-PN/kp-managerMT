import Foundation

public enum LedgerError: Error, LocalizedError, Equatable {
    case invalid(String), notFound, duplicateCustomer, duplicateTransaction, overpayment, overflow
    case unsupportedSchema, corruptBackup, storage(String), consentRequired, unavailable(String)
    public var errorDescription: String? {
        switch self {
        case .invalid(let text), .storage(let text), .unavailable(let text): return text
        case .notFound: return "Không tìm thấy dữ liệu."
        case .duplicateCustomer: return "Tên khách đã tồn tại. Hãy kiểm tra và xác nhận tạo riêng."
        case .duplicateTransaction: return "Dòng này trùng giao dịch đã nhập. Hãy kiểm tra lại."
        case .overpayment: return "Số tiền vượt dư nợ hoặc làm mất cân đối sổ. Hãy ghi khoản trả trước riêng nếu cần."
        case .overflow: return "Số tiền vượt giới hạn tính toán."
        case .unsupportedSchema: return "Phiên bản dữ liệu chưa được hỗ trợ. Hãy cập nhật ứng dụng."
        case .corruptBackup: return "Bản sao lưu không hợp lệ hoặc mật khẩu không đúng."
        case .consentRequired: return "Cần đồng ý trước khi gửi dữ liệu đến dịch vụ trực tuyến."
        }
    }
}

public enum TextKey {
    public static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN"))
            .replacingOccurrences(of: "đ", with: "d").replacingOccurrences(of: "Đ", with: "d")
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

public struct Customer: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var nickname: String
    public var phone: String
    public var address: String
    public var note: String
    public var createdAt: Date
    public var updatedAt: Date
    public var mergedInto: UUID?
    public init(id: UUID = UUID(), name: String, nickname: String = "", phone: String = "", address: String = "", note: String = "", now: Date = Date()) {
        self.id = id; self.name = name; self.nickname = nickname; self.phone = phone
        self.address = address; self.note = note; self.createdAt = now; self.updatedAt = now
    }
    public func matches(_ query: String) -> Bool {
        let key = TextKey.normalize(query)
        return key.isEmpty || [name, nickname, phone, address].contains { TextKey.normalize($0).contains(key) }
    }
}

public enum TransactionKind: String, Codable, CaseIterable, Sendable {
    case debt, loan, collection, borrowing, repayment, advanceReceived, advanceUsed
    case adjustmentIncrease, adjustmentDecrease, reversal
    public var title: String {
        switch self {
        case .debt: return "Ghi nợ"
        case .loan: return "Cho vay"
        case .collection: return "Thu nợ / thu khoản vay"
        case .borrowing: return "Tôi vay khách"
        case .repayment: return "Tôi trả khoản vay"
        case .advanceReceived: return "Nhận trả trước"
        case .advanceUsed: return "Cấn trừ trả trước"
        case .adjustmentIncrease: return "Điều chỉnh tăng phải thu"
        case .adjustmentDecrease: return "Điều chỉnh giảm phải thu"
        case .reversal: return "Hoàn tác"
        }
    }
    public static var editable: [Self] { allCases.filter { $0 != .reversal } }
    public var increasesReceivable: Bool { [.debt, .loan, .adjustmentIncrease].contains(self) }
}
public enum EntrySource: String, Codable, Sendable { case manual, voice, ocr, restore }
public enum EntryStatus: String, Codable, Sendable { case posted }

public struct DebtTransaction: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var customerID: UUID
    public var amount: Int64
    public var kind: TransactionKind
    public var createdAt: Date
    public var effectiveDate: Date
    public var updatedAt: Date
    public var dueDate: Date?
    public var note: String
    public var source: EntrySource
    public var status: EntryStatus
    public var reversalOf: UUID?
    public var attachmentIDs: [UUID]
    public var importKey: String?
    public init(id: UUID = UUID(), customerID: UUID, amount: Int64, kind: TransactionKind,
                effectiveDate: Date = Date(), dueDate: Date? = nil, note: String = "",
                source: EntrySource = .manual, reversalOf: UUID? = nil,
                attachmentIDs: [UUID] = [], importKey: String? = nil, now: Date = Date()) {
        self.id = id; self.customerID = customerID; self.amount = amount; self.kind = kind
        self.createdAt = now; self.updatedAt = now; self.effectiveDate = effectiveDate
        self.dueDate = dueDate; self.note = note; self.source = source; self.status = .posted
        self.reversalOf = reversalOf; self.attachmentIDs = attachmentIDs; self.importKey = importKey
    }
}

public struct AuditEvent: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var entityID: UUID
    public var event: String
    public var timestamp: Date = Date()
    public var oldValue: String?
    public var newValue: String?
    public var source: EntrySource
    public var reason: String
    public init(entityID: UUID, event: String, oldValue: String? = nil, newValue: String? = nil, source: EntrySource = .manual, reason: String = "") {
        self.entityID = entityID; self.event = event; self.oldValue = oldValue
        self.newValue = newValue; self.source = source; self.reason = reason
    }
}
public struct Attachment: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var data: Data
    public var mediaType: String
    public init(id: UUID = UUID(), data: Data, mediaType: String = "image/jpeg") {
        self.id = id; self.data = data; self.mediaType = mediaType
    }
}
public struct SavedDraft: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var data: Data
    public init(id: UUID, data: Data) { self.id = id; self.data = data }
}
public struct LedgerSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 1
    public var customers: [Customer] = []
    public var transactions: [DebtTransaction] = []
    public var audit: [AuditEvent] = []
    public var attachments: [Attachment] = []
    public var drafts: [SavedDraft] = []
    public init() {}
    public func rootID(_ id: UUID) throws -> UUID {
        var current = id, visited = Set<UUID>()
        while true {
            guard visited.insert(current).inserted, let customer = customers.first(where: { $0.id == current }) else { throw LedgerError.invalid("Liên kết khách hàng không hợp lệ.") }
            guard let next = customer.mergedInto else { return current }
            current = next
        }
    }
    public func entries(for customerID: UUID) throws -> [DebtTransaction] {
        let root = try rootID(customerID)
        let members = try Set(customers.filter { try rootID($0.id) == root }.map(\.id))
        return transactions.filter { members.contains($0.customerID) }
    }
}

public enum JSONCoding {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    public static func string<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try encode(value), as: UTF8.self)
    }
}
