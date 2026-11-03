import SwiftUI
import SoNoCore

struct VoiceInputView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = AppleVoiceRecognition()
    @StateObject private var recorder = ProxyAudioRecorder()
    @State private var text = ""
    @State private var allowAppleServer = false
    @State private var provider = "apple"
    @State private var draft: VoiceDraft?
    @State private var selectedCustomerID: UUID?
    @State private var answer: String?
    @State private var editor = false
    @State private var audio: Data?
    @State private var consent = false
    @State private var networkTask: Task<Void, Never>?
    @State private var saveTask: Task<Void, Never>?
    @State private var processing = false
    @State private var loaded = false
    private let draftID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    var body: some View {
        Form {
            Section("Nói như bạn vẫn ghi sổ") {
                Text("“Anh Nam lấy thêm hàng 350 nghìn”\n“Chị Lan vừa trả 2 triệu rưỡi”\n“Anh Minh còn nợ bao nhiêu?”").font(.subheadline).foregroundStyle(.secondary)
                Picker("Nhận dạng", selection: $provider) { Text("Apple Speech").tag("apple"); Text("Proxy AI đã ghép nối").tag("proxy") }.disabled(speech.recording || recorder.recording || processing)
                if provider == "apple" {
                    Text(speech.onDeviceAvailable ? "Thiết bị báo có hỗ trợ nhận dạng tại chỗ." : "Nhận dạng tiếng Việt ngoại tuyến chưa khả dụng trên thiết bị này.").font(.caption)
                    Toggle("Cho phép Apple xử lý trực tuyến lần này", isOn: $allowAppleServer).disabled(speech.recording)
                    Text("Khi bật, âm thanh có thể được gửi đến Apple để nhận dạng. Không bật thì chỉ yêu cầu xử lý trên thiết bị.").font(.caption).foregroundStyle(.secondary)
                } else { Text("Thu tối đa 60 giây. Sau khi dừng, bạn chọn gửi hoặc hủy. Bản ghi tạm bị xóa; không tự gửi lại.").font(.caption) }
                Button { Task { await record() } } label: {
                    Label(speech.recording || recorder.recording ? "Dừng thu âm" : "Bắt đầu nói", systemImage: speech.recording || recorder.recording ? "stop.circle.fill" : "mic.circle.fill").font(.title3).frame(maxWidth: .infinity).padding(.vertical, 10)
                }.buttonStyle(.borderedProminent).disabled(processing)
                if processing { ProgressView("Đang nhận dạng…"); Button("Hủy yêu cầu") { networkTask?.cancel(); processing = false; audio = nil } }
                if let error = speech.error { Text(error).foregroundStyle(.red).font(.caption) }
            }
            Section("Văn bản — có thể sửa khi không có mạng") {
                TextEditor(text: $text).frame(minHeight: 120).accessibilityLabel("Nội dung lời nói")
                Button("Phân tích yêu cầu") {
                    draft = VietnameseVoiceParser().parse(text, customers: model.customers, now: Date())
                    selectedCustomerID = draft?.candidateIDs.count == 1 ? draft?.candidateIDs.first : nil
                    answer = nil
                }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || speech.recording || processing)
            }
            if let draft {
                Section("Kiểm tra kết quả") {
                    ForEach(draft.warnings, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                    if ![.todayCollections, .overdue].contains(draft.intent) {
                        Picker("Khách hàng", selection: $selectedCustomerID) {
                            Text("Chọn đúng khách").tag(nil as UUID?)
                            ForEach(model.customers) { customer in Text(customer.name + (customer.phone.isEmpty ? "" : " · " + customer.phone)).tag(Optional(customer.id)) }
                        }
                    }
                    if let amount = draft.amount { LabeledContent("Số tiền đề xuất", value: VND.string(amount)) }
                    if draft.isQuery {
                        Button("Tra cứu trong sổ") {
                            do { answer = try model.answer(for: draft, selectedCustomerID: selectedCustomerID) }
                            catch { model.error = error.localizedDescription }
                        }
                    } else {
                        Text("Mở bản nháp để kiểm tra ngày, số tiền và chọn loại giao dịch trước khi xác nhận.").font(.caption)
                        Button("Mở bản nháp giao dịch") { editor = true }.disabled(selectedCustomerID == nil)
                    }
                }
            }
            if let answer { Section("Kết quả từ dữ liệu trên iPhone") { Text(answer).textSelection(.enabled) } }
            ErrorMessage()
        }.navigationTitle("Nhập bằng giọng nói")
            .toolbar { Button("Đóng") { dismiss() } }
            .task {
                guard !loaded else { return }; loaded = true
                do {
                    if let ledger = model.ledger, let saved = try await ledger.loadDraft(draftID), let restored = String(data: saved.data, encoding: .utf8) { text = restored }
                } catch { model.error = error.localizedDescription }
            }
            .onChange(of: speech.transcript) { _, value in text = value }
            .onChange(of: text) { _, value in
                draft = nil; answer = nil
                saveTask?.cancel()
                saveTask = Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled, let ledger = model.ledger else { return }
                    do { try await ledger.saveDraft(SavedDraft(id: draftID, data: Data(value.utf8))) }
                    catch { model.error = error.localizedDescription }
                }
            }
            .onDisappear {
                speech.cancel(); recorder.discard(); networkTask?.cancel(); saveTask?.cancel()
                let savedText = text
                Task { if let ledger = model.ledger { try? await ledger.saveDraft(SavedDraft(id: draftID, data: Data(savedText.utf8))) } }
            }
            .confirmationDialog("Gửi bản ghi âm vừa thu tới proxy AI đã ghép nối? Có thể phát sinh chi phí theo cấu hình proxy.", isPresented: $consent, titleVisibility: .visible) {
                Button("Đồng ý gửi bản ghi này") { transcribe() }
                Button("Hủy và bỏ bản ghi", role: .cancel) { audio = nil }
            }
            .sheet(isPresented: $editor) {
                if let draft { NavigationStack {
                    TransactionEditorView(customerID: selectedCustomerID, amount: draft.amount, kind: draft.intent == .collection ? .collection : .debt, date: draft.effectiveDate, note: draft.transcript, source: .voice) {
                        text = ""; self.draft = nil
                    }
                } }
            }
    }
    private func record() async {
        do {
            if provider == "apple" {
                if speech.recording { speech.stop() } else { speech.transcript = ""; try await speech.start(allowAppleServer: allowAppleServer) }
            } else {
                if recorder.recording { audio = try recorder.finish(); consent = true }
                else { try await recorder.start() }
            }
        } catch { model.error = error.localizedDescription }
    }
    private func transcribe() {
        guard let audio else { return }; self.audio = nil; processing = true
        networkTask = Task {
            defer { processing = false }
            do { let result = try await OnlineAIClient().transcribe(audio: audio, consent: true); try Task.checkCancellation(); text = result }
            catch is CancellationError { }
            catch { if !Task.isCancelled { model.error = error.localizedDescription } }
        }
    }
}
