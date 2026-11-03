import SwiftUI
import PhotosUI
import SoNoCore

struct LedgerView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var customerID: UUID?
    @State private var filter = "all"
    @State private var byDate = false
    @State private var date = Date()
    @State private var adding = false
    @State private var visibleCount = 100
    private var entries: [DebtTransaction] {
        let source = customerID.map { model.entries(for: $0) } ?? model.state.transactions
        let key = TextKey.normalize(query)
        let openIDs = Set((model.summary?.balances.values.flatMap(\.outstanding) ?? []).map(\.id))
        return source.filter { entry in
            let matchesText = query.isEmpty || TextKey.normalize(model.customerName(entry.customerID) + " " + entry.note + " " + entry.kind.title).contains(key) || String(entry.amount).contains(query.replacingOccurrences(of: ".", with: ""))
            let matchesState = filter == "all" || filter == "open" && openIDs.contains(entry.id) || filter == "overdue" && openIDs.contains(entry.id) && (entry.dueDate.map { $0 < VietnameseDate.calendar.startOfDay(for: Date()) } ?? false)
            return matchesText && matchesState && (!byDate || VietnameseDate.calendar.isDate(entry.effectiveDate, inSameDayAs: date))
        }.sorted { $0.effectiveDate > $1.effectiveDate }
    }
    var body: some View {
        List {
            Section("Bộ lọc") {
                Picker("Khách hàng", selection: $customerID) {
                    Text("Tất cả").tag(nil as UUID?)
                    ForEach(model.customers) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("Tình trạng", selection: $filter) { Text("Tất cả").tag("all"); Text("Còn nợ").tag("open"); Text("Quá hạn").tag("overdue") }
                Toggle("Lọc theo ngày", isOn: $byDate)
                if byDate { DatePicker("Ngày giao dịch", selection: $date, displayedComponents: .date) }
            }
            ErrorMessage()
            Section("\(entries.count) giao dịch") {
                ForEach(entries.prefix(visibleCount)) { entry in NavigationLink { TransactionDetailView(entry: entry) } label: { TransactionRow(entry: entry) } }
                if entries.count > visibleCount { Button("Xem thêm 100 giao dịch") { visibleCount += 100 } }
                if entries.isEmpty { Text("Không có giao dịch phù hợp.").foregroundStyle(.secondary) }
            }
        }.navigationTitle("Sổ giao dịch").searchable(text: $query, prompt: "Tên, số tiền hoặc ghi chú")
            .toolbar { Button { adding = true } label: { Label("Thêm giao dịch", systemImage: "plus") } }
            .sheet(isPresented: $adding) { NavigationStack { TransactionEditorView() } }
    }
}

struct TransactionEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var customerID: UUID?
    @State private var amount: String
    @State private var kind: TransactionKind
    @State private var effectiveDate: Date
    @State private var hasDue = false
    @State private var dueDate = Date()
    @State private var note: String
    @State private var confirmed = false
    @State private var photo: PhotosPickerItem?
    @State private var attachments: [Attachment] = []
    @State private var reason = ""
    var source: EntrySource
    var original: DebtTransaction?
    var onSaved: (() -> Void)?
    init(customerID: UUID? = nil, amount: Int64? = nil, kind: TransactionKind = .debt, date: Date = Date(), note: String = "", source: EntrySource = .manual, original: DebtTransaction? = nil, onSaved: (() -> Void)? = nil) {
        _customerID = State(initialValue: original?.customerID ?? customerID)
        _amount = State(initialValue: (original?.amount ?? amount).map(String.init) ?? "")
        _kind = State(initialValue: original?.kind ?? kind); _effectiveDate = State(initialValue: original?.effectiveDate ?? date)
        _note = State(initialValue: original?.note ?? note); _hasDue = State(initialValue: original?.dueDate != nil)
        _dueDate = State(initialValue: original?.dueDate ?? Date())
        self.source = source; self.original = original; self.onSaved = onSaved
    }
    private var parsedAmount: Int64? { VietnameseMoneyParser().parse(amount).amount }
    var body: some View {
        Form {
            Section("Giao dịch") {
                Picker("Khách hàng", selection: $customerID) {
                    Text("Chọn khách hàng").tag(nil as UUID?)
                    ForEach(model.customers) { Text($0.name).tag(Optional($0.id)) }
                    if let original, !model.customers.contains(where: { $0.id == original.customerID }) { Text(model.customerName(original.customerID)).tag(Optional(original.customerID)) }
                }.disabled(original != nil)
                Picker("Loại", selection: $kind) { ForEach(TransactionKind.editable, id: \.self) { Text($0.title).tag($0) } }.accessibilityIdentifier("transaction.kind")
                TextField("Số tiền (đồng)", text: $amount).keyboardType(.numberPad).accessibilityIdentifier("transaction.amount")
                if let parsedAmount { Text(VND.string(parsedAmount)).font(.title3.bold()).foregroundStyle(.teal) }
                DatePicker("Ngày giao dịch", selection: $effectiveDate, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                Toggle("Có ngày đến hạn", isOn: $hasDue)
                if hasDue { DatePicker("Hạn trả", selection: $dueDate, in: effectiveDate..., displayedComponents: .date) }
                TextField("Ghi chú / lý do điều chỉnh", text: $note, axis: .vertical)
                if original == nil {
                    PhotosPicker(selection: $photo, matching: .images) { Label("Thêm ảnh chứng từ", systemImage: "paperclip") }
                    ForEach(attachments) { image in Text("Đã đính kèm ảnh \(image.id.uuidString.prefix(6))").font(.caption) }
                }
            }
            if original != nil { Section("Điều chỉnh có lưu lịch sử") { TextField("Lý do bắt buộc", text: $reason); Text("Ứng dụng ghi hoàn tác và giao dịch thay thế trong cùng một lần lưu.").font(.caption) } }
            Section("Kiểm tra trước khi ghi") {
                if let customerID { LabeledContent("Phải thu hiện tại", value: VND.string(model.balance(for: customerID).receivable)) }
                Text("Thu nợ không được vượt phải thu. Nhận tiền dư cần ghi riêng là Nhận trả trước. Ngày và loại giao dịch cần được đối chiếu.").font(.caption).foregroundStyle(.secondary)
                Toggle("Tôi đã kiểm tra khách, số tiền, ngày và loại", isOn: $confirmed).accessibilityIdentifier("transaction.confirmed")
            }
            ErrorMessage()
        }.navigationTitle(original == nil ? "Ghi giao dịch" : "Điều chỉnh giao dịch")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ghi sổ") { Task { await save() } }.disabled(!confirmed || parsedAmount == nil || customerID == nil || model.busy || original != nil && reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("transaction.save") }
            }
            .onChange(of: photo) { _, value in Task {
                do {
                    if let data = try await value?.loadTransferable(type: Data.self) {
                        guard data.count <= 20_000_000 else { throw LedgerError.invalid("Ảnh vượt 20 MB.") }
                        attachments.append(Attachment(data: data))
                    }
                } catch { model.error = error.localizedDescription }
            } }
            .onChange(of: amount) { _, _ in confirmed = false }
            .onChange(of: customerID) { _, _ in confirmed = false }
            .onChange(of: kind) { _, _ in confirmed = false }
            .onChange(of: effectiveDate) { _, _ in confirmed = false }
    }
    private func save() async {
        guard let ledger = model.ledger, let customerID, let parsedAmount else { return }
        let entry = DebtTransaction(customerID: customerID, amount: parsedAmount, kind: kind, effectiveDate: effectiveDate, dueDate: hasDue ? dueDate : nil, note: note, source: source,
                                    attachmentIDs: original?.attachmentIDs ?? attachments.map(\.id))
        let success = await model.perform {
            if let original { try await ledger.correct(original.id, replacement: entry, reason: reason) }
            else { try await ledger.post([entry], attachments: attachments, confirmed: confirmed) }
        }
        if success { onSaved?(); dismiss() }
    }
}

struct TransactionDetailView: View {
    @EnvironmentObject private var model: AppModel
    var entry: DebtTransaction
    @State private var reason = ""
    @State private var confirmReverse = false
    @State private var editing = false
    private var reversed: Bool { model.state.transactions.contains { $0.reversalOf == entry.id } }
    var body: some View {
        List {
            Section { TransactionRow(entry: entry); Text(entry.note); LabeledContent("Nguồn", value: sourceTitle); Text("Mã: \(entry.id.uuidString)").font(.caption).textSelection(.enabled) }
            if let due = entry.dueDate { Section("Hạn trả") { Text(VietnameseDate.display(due)) } }
            if !entry.attachmentIDs.isEmpty {
                Section("Chứng từ gốc") {
                    ForEach(model.state.attachments.filter { entry.attachmentIDs.contains($0.id) }) { attachment in
                        if let image = UIImage(data: attachment.data) { Image(uiImage: image).resizable().scaledToFit().accessibilityLabel("Ảnh chứng từ nguồn") }
                    }
                }
            }
            if reversed { Label("Đã hoàn tác — giữ nguyên bản ghi gốc", systemImage: "arrow.uturn.backward") }
            else if entry.kind != .reversal {
                Section("Sửa có lưu dấu vết") {
                    Button("Điều chỉnh số tiền, ngày hoặc ghi chú") { editing = true }
                    TextField("Lý do hoàn tác", text: $reason)
                    Button("Hoàn tác giao dịch", role: .destructive) { confirmReverse = true }.disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy)
                    Text("Nếu hoàn tác làm số dư không hợp lệ, cần hoàn tác các khoản thu liên quan trước.").font(.caption).foregroundStyle(.secondary)
                }
            }
            NavigationLink("Nhật ký liên quan") { AuditLogView(entityID: entry.id) }
            ErrorMessage()
        }.navigationTitle("Chi tiết giao dịch")
            .sheet(isPresented: $editing) { NavigationStack { TransactionEditorView(original: entry) } }
            .confirmationDialog("Xác nhận hoàn tác \(VND.string(entry.amount))?", isPresented: $confirmReverse, titleVisibility: .visible) {
                Button("Hoàn tác và ghi nhật ký", role: .destructive) { Task {
                    guard let ledger = model.ledger else { return }
                    _ = await model.perform { try await ledger.reverse(entry.id, reason: reason) }
                } }
            }
    }
    private var sourceTitle: String {
        switch entry.source { case .manual: return "Nhập thủ công"; case .voice: return "Giọng nói"; case .ocr: return "Quét sổ"; case .restore: return "Khôi phục" }
    }
}
