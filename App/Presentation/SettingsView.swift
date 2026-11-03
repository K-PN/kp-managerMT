import SwiftUI
import UniformTypeIdentifiers
import LocalAuthentication
import SoNoCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("appLock") private var appLock = false
    @AppStorage("remindersEnabled") private var reminders = false
    var body: some View {
        Form {
            Section("Cá nhân hóa") {
                Picker("Giao diện", selection: $appearance) { Text("Theo hệ thống").tag("system"); Text("Sáng").tag("light"); Text("Tối").tag("dark") }
                Toggle("Khóa bằng Face ID / mật mã iPhone", isOn: Binding(get: { appLock }, set: { value in Task { await setLock(value) } }))
                Toggle("Nhắc ngày đến hạn", isOn: Binding(get: { reminders }, set: { value in Task { await setReminders(value) } }))
                Text("Thông báo không hiển thị tên và số tiền trên màn hình khóa. Ứng dụng cập nhật lịch nhắc khi mở sổ; iOS có thể hạn chế hoặc trì hoãn thông báo.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Dữ liệu của bạn") {
                NavigationLink("Sao lưu và khôi phục") { BackupView() }
                NavigationLink("Nhật ký thay đổi") { AuditLogView() }
                NavigationLink("Báo cáo và xuất sổ") { ReportsView() }
            }
            Section("Giọng nói và chữ viết tay") {
                NavigationLink("Ghép nối proxy AI tùy chọn") { AISettingsView() }
                Text("Quản lý khách và công nợ dùng được khi không có mạng. Chỉ gửi âm thanh hoặc trang ảnh bạn chọn sau khi bạn đồng ý. Không gửi cơ sở dữ liệu.").font(.caption)
            }
            Section("Sổ Nợ AI · 1.0") {
                LabeledContent("Tiền tệ", value: "VND · đồng nguyên")
                LabeledContent("Múi giờ", value: "Asia/Ho_Chi_Minh")
                Text("Sổ hiện nằm trên iPhone này. Hãy xuất bản sao lưu sang một nơi khác; mất hoặc hỏng máy có thể khiến mất dữ liệu chưa sao lưu.").font(.caption).foregroundStyle(.secondary)
            }
            ErrorMessage()
        }.navigationTitle("Cài đặt")
    }
    private func setLock(_ enabled: Bool) async {
        do {
            let context = LAContext()
            let result = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: enabled ? "Bật khóa sổ công nợ" : "Tắt khóa sổ công nợ")
            if result { appLock = enabled; model.locked = false }
        } catch { model.error = error.localizedDescription }
    }
    private func setReminders(_ enabled: Bool) async {
        if enabled {
            do {
                let granted = try await model.reminders.requestAuthorization()
                if granted { reminders = true; try await model.reminders.synchronize(snapshot: model.state) }
                else { reminders = false; model.error = "Chưa có quyền thông báo. Bạn có thể bật trong Cài đặt iPhone." }
            } catch { model.error = error.localizedDescription }
        } else { reminders = false; await model.reminders.disable() }
    }
}

struct BinaryDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw LedgerError.corruptBackup }; self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct BackupView: View {
    @EnvironmentObject private var model: AppModel
    @State private var password = ""
    @State private var document: BinaryDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var restoreData: Data?
    @State private var restoreName = ""
    @State private var confirm = false
    @State private var busy = false
    @State private var message: String?
    @State private var shareURL: URL?
    var body: some View {
        Form {
            Section("Mật khẩu sao lưu") {
                SecureField("Để trống nếu không mã hóa", text: $password).textContentType(.newPassword)
                Text("Khi đặt mật khẩu: tối thiểu 10 ký tự. Bạn cần đúng mật khẩu để khôi phục; ứng dụng không có cách lấy lại. Mật khẩu không được lưu.").font(.caption)
            }
            Section("Xuất toàn bộ dữ liệu") {
                Button("Tạo bản sao lưu") { Task { await export() } }.disabled(busy)
                if let shareURL {
                    Button("Lưu vào Tệp") { exporting = true }
                    ShareLink("Chia sẻ bản sao lưu", item: shareURL)
                }
                Text("Gồm khách hàng, giao dịch, nhật ký, ảnh và bản nháp. Lưu thêm một bản ngoài iPhone này. Tệp không mã hóa có thể bị đọc bởi người có tệp.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Khôi phục từ tệp .sono") {
                Button("Chọn bản sao lưu") { importing = true }.disabled(busy)
                Text("Khôi phục sẽ thay sổ hiện tại bằng dữ liệu trong tệp. Nhật ký hiện tại được giữ lại. Hãy xuất sổ hiện tại trước khi khôi phục.").font(.caption).foregroundStyle(.secondary)
            }
            if busy { ProgressView("Đang xử lý…") }
            if let message { Text(message).foregroundStyle(.teal) }
            ErrorMessage()
        }.navigationTitle("Sao lưu / khôi phục")
            .fileExporter(isPresented: $exporting, document: document, contentType: .data, defaultFilename: "SoNoAI-\(ISO8601DateFormatter().string(from: Date()).prefix(10)).sono") { result in
                if case .failure(let error) = result { model.error = error.localizedDescription }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
                Task {
                    busy = true; defer { busy = false }
                    do {
                        let url = try result.get(); let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        restoreData = try await Task.detached {
                            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                            guard size > 0 && size <= 512_000_000 else { throw LedgerError.corruptBackup }
                            return try Data(contentsOf: url)
                        }.value
                        restoreName = url.lastPathComponent; confirm = true
                    } catch { model.error = error.localizedDescription }
                }
            }
            .confirmationDialog("Khôi phục từ \(restoreName)? Dữ liệu hiện tại sẽ được thay bằng bản sao lưu, sau khi tệp vượt qua kiểm tra.", isPresented: $confirm, titleVisibility: .visible) {
                Button("Xác nhận khôi phục", role: .destructive) { Task { await restore() } }
                Button("Hủy", role: .cancel) { restoreData = nil }
            }
            .onDisappear { password = ""; restoreData = nil; if let shareURL { try? FileManager.default.removeItem(at: shareURL) } }
    }
    private func export() async {
        guard let backup = model.backup else { return }; busy = true; defer { busy = false }
        do {
            let data = try await backup.export(password: password.isEmpty ? nil : password)
            document = BinaryDocument(data: data)
            if let shareURL { try? FileManager.default.removeItem(at: shareURL) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("SoNoAI-\(UUID().uuidString).sono")
            try await Task.detached { try data.write(to: url, options: [.atomic, .completeFileProtection]) }.value
            shareURL = url
            message = "Đã tạo tệp. Hãy chọn Lưu vào Tệp hoặc Chia sẻ để giữ bản sao bên ngoài ứng dụng."
        } catch { model.error = error.localizedDescription }
    }
    private func restore() async {
        guard let backup = model.backup, let restoreData else { return }; busy = true; defer { busy = false; self.restoreData = nil }
        do {
            try await backup.restore(restoreData, password: password.isEmpty ? nil : password, confirmed: true)
            await model.refresh(); message = "Đã khôi phục và ghi nhật ký."
        } catch { model.error = error.localizedDescription }
    }
}

struct AISettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var endpoint = ""
    @State private var token = ""
    @State private var minutes = 15
    @State private var status = "Chưa ghép nối"
    var body: some View {
        Form {
            Section("Phiên proxy riêng — tùy chọn") {
                Text("Dùng mã phiên ngắn hạn do proxy riêng cấp cho iPhone này. Không nhập API key OpenAI hoặc nhà cung cấp khác. Proxy cần xác thực thiết bị, giới hạn yêu cầu và ngân sách trước khi cấp phiên.").font(.caption)
                TextField("https://proxy-cua-ban/v1", text: $endpoint).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                SecureField("Mã phiên ngắn hạn", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                Stepper("Hiệu lực còn lại: \(minutes) phút", value: $minutes, in: 1...60)
                Button("Lưu phiên vào Keychain") {
                    do {
                        guard let url = URL(string: endpoint) else { throw LedgerError.invalid("URL không hợp lệ.") }
                        try AIKeychain.save(AIConnection(baseURL: url, token: token, expiresAt: Date().addingTimeInterval(TimeInterval(minutes * 60))))
                        token = ""; status = "Đã lưu phiên. Mỗi lần gửi vẫn cần bạn đồng ý."
                    } catch { model.error = error.localizedDescription }
                }
                Button("Xóa phiên", role: .destructive) { AIKeychain.clear(); token = ""; status = "Đã xóa phiên AI." }
                Text(status).font(.caption)
            }
            Section("Nếu chưa có proxy") { Text("Để trống cấu hình này. Bạn vẫn quản lý sổ ngoại tuyến, thử Apple Speech nếu thiết bị hỗ trợ và quét bằng Vision. Xem README và docs/AI_PROXY.md trong mã nguồn để triển khai proxy bảo mật.").font(.caption) }
            ErrorMessage()
        }.navigationTitle("Kết nối AI online")
            .task {
                do { if let saved = try AIKeychain.load() { endpoint = saved.baseURL.absoluteString; status = saved.expiresAt > Date() ? "Phiên hết hạn lúc \(VietnameseDate.display(saved.expiresAt))" : "Phiên đã hết hạn; cần ghép nối lại." } }
                catch { model.error = error.localizedDescription }
            }
            .onDisappear { token = "" }
    }
}
