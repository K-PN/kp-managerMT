import SwiftUI
import PhotosUI
import SoNoCore

struct LedgerView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var customerID: UUID?
    @State private var account: String
    @State private var kind: TransactionKind?
    @State private var openOnly: Bool
    @State private var byDate: Bool
    @State private var from: Date
    @State private var to: Date
    @State private var adding = false
    @State private var visibleCount = 100
    init(kind: TransactionKind? = nil, from: Date? = nil, to: Date? = nil, account: String = "all", openOnly: Bool = false) {
        _kind = State(initialValue: kind); _account = State(initialValue: account); _openOnly = State(initialValue: openOnly)
        _byDate = State(initialValue: from != nil); _from = State(initialValue: from ?? Date()); _to = State(initialValue: to ?? Date())
    }
    private var entries: [DebtTransaction] {
        let source = customerID.map { model.entries(for: $0) } ?? model.state.transactions
        let openIDs = Set((model.summary?.balances.values.flatMap { $0.outstanding + $0.goodsOutstanding } ?? []).map(\.id))
        let key = TextKey.normalize(query)
        return source.filter { entry in
            let matchesText = query.isEmpty || TextKey.normalize(model.customerName(entry.customerID) + " " + entry.note + " " + (entry.goodsDescription ?? "") + " " + entry.kind.title).contains(key) || String(entry.amount).contains(query.replacingOccurrences(of: ".", with: ""))
            let matchesAccount = account == "all" || account == "goods" && [.purchase, .supplierPayment].contains(entry.kind) || account == "debt" && (entry.kind.increasesReceivable || [.collection, .adjustmentDecrease, .advanceUsed].contains(entry.kind))
            return matchesText && matchesAccount && (kind == nil || entry.kind == kind) && (!openOnly || openIDs.contains(entry.id)) && (!byDate || LedgerDateRange.contains(entry.effectiveDate, from: from, through: to))
        }.sorted { $0.effectiveDate > $1.effectiveDate }
    }
    var body: some View {
        List {
            Section {
                Picker("Nhóm", selection: $account) { Text("Tất cả").tag("all"); Text("Nợ khách").tag("debt"); Text("Tiền hàng").tag("goods") }.pickerStyle(.segmented)
                Picker("Khách / nhà cung cấp", selection: $customerID) {
                    Text("Tất cả").tag(nil as UUID?)
                    ForEach(model.customers) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("Loại giao dịch", selection: $kind) {
                    Text("Tất cả").tag(nil as TransactionKind?)
                    ForEach(TransactionKind.editable, id: \.self) { Text($0.title).tag(Optional($0)) }
                }
                Toggle("Chỉ khoản còn nợ", isOn: $openOnly)
                Toggle("Lọc từ ngày - đến ngày", isOn: $byDate).accessibilityIdentifier("ledger.dateFilter")
                if byDate {
                    DatePicker("Từ ngày", selection: $from, in: ...Date(), displayedComponents: .date).accessibilityIdentifier("ledger.from")
                    DatePicker("Đến ngày", selection: $to, in: from...max(from, Date()), displayedComponents: .date).accessibilityIdentifier("ledger.to")
                }
            }
            ErrorMessage()
            Section("\(entries.count) giao dịch") {
                ForEach(entries.prefix(visibleCount)) { entry in NavigationLink { TransactionDetailView(entry: entry) } label: { TransactionRow(entry: entry) } }
                if entries.count > visibleCount { Button("Xem thêm 100 giao dịch") { visibleCount += 100 } }
                if entries.isEmpty { Text("Không có giao dịch phù hợp.").foregroundStyle(.secondary) }
            }
        }.navigationTitle("Sổ giao dịch").searchable(text: $query, prompt: "Khách, mặt hàng hoặc số tiền")
            .toolbar { Button { adding = true } label: { Label("Thêm giao dịch", systemImage: "plus") } }
            .sheet(isPresented: $adding) { NavigationStack { TransactionEditorView() } }
            .onChange(of: from) { _, value in if to < value { to = value }; visibleCount = 100 }
            .onChange(of: to) { _, _ in visibleCount = 100 }
            .onChange(of: account) { _, _ in kind = nil; visibleCount = 100 }
    }
}

struct TransactionEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var customerID: UUID?
    @State private var amount: String
    @State private var paid = "0"
    @State private var goods: String
    @State private var kind: TransactionKind
    @State private var effectiveDate: Date
    @State private var note: String
    @State private var confirmed = false
    private enum MoneyField: Hashable { case amount, paid }
    @FocusState private var moneyFocus: MoneyField?
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
        _note = State(initialValue: original?.note ?? note); _goods = State(initialValue: original?.goodsDescription ?? "")
        self.source = source; self.original = original; self.onSaved = onSaved
    }
    private var parsedAmount: Int64? { VietnameseMoneyParser().parse(amount).amount }
    private var paidAmount: Int64? { paid.trimmingCharacters(in: .whitespaces).isEmpty || paid == "0" ? 0 : VietnameseMoneyParser().parse(paid).amount }
    private var preview: TransactionProposal? { try? proposal() }
    private var availableKinds: [TransactionKind] {
        if let original, !TransactionKind.editable.contains(original.kind) { return TransactionKind.editable + [original.kind] }
        return TransactionKind.editable
    }
    var body: some View {
        Form {
            Section {
                Picker("Loại", selection: $kind) { ForEach(availableKinds, id: \.self) { Text($0.title).tag($0) } }.accessibilityIdentifier("transaction.kind")
                Picker(kind == .purchase || kind == .supplierPayment ? "Nhà cung cấp" : "Khách hàng", selection: $customerID) {
                    Text("Chọn người giao dịch").tag(nil as UUID?)
                    ForEach(model.customers) { Text($0.name).tag(Optional($0.id)) }
                    if let original, !model.customers.contains(where: { $0.id == original.customerID }) { Text(model.customerName(original.customerID)).tag(Optional(original.customerID)) }
                }.disabled(original != nil).accessibilityIdentifier("transaction.customer")
                if kind == .purchase {
                    TextField("Mặt hàng / số lượng", text: $goods, axis: .vertical).accessibilityIdentifier("transaction.goods")
                }
                TextField(kind == .purchase ? "Tổng tiền hàng (đồng)" : "Số tiền (đồng)", text: $amount).keyboardType(.numberPad).focused($moneyFocus, equals: .amount).accessibilityIdentifier("transaction.amount")
                if let parsedAmount { Text(VND.string(parsedAmount)).font(.title2.bold()).foregroundStyle(.teal) }
                if kind == .purchase && original == nil {
                    TextField("Đã trả (đồng)", text: $paid).keyboardType(.numberPad).focused($moneyFocus, equals: .paid).accessibilityIdentifier("transaction.paid")
                    if let total = parsedAmount, let paidAmount, total >= paidAmount { LabeledContent("Nợ lại lần này", value: VND.string(total - paidAmount)) }
                }
                DatePicker("Ngày giao dịch", selection: $effectiveDate, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                if original == nil {
                    PhotosPicker(selection: $photo, matching: .images) { Label("Ảnh chứng từ", systemImage: "paperclip") }
                    if !attachments.isEmpty { Text("\(attachments.count) ảnh").font(.caption).foregroundStyle(.secondary) }
                }
            }
            if original != nil { Section { TextField("Lý do điều chỉnh", text: $reason) } }
            Section("Đối chiếu") {
                if let customerID {
                    let balance = model.balance(for: customerID)
                    LabeledContent(kind == .purchase || kind == .supplierPayment ? "Nợ tiền hàng cũ" : "Nợ khách cũ", value: VND.string(kind == .purchase || kind == .supplierPayment ? balance.goodsPayable : balance.receivable))
                }
                if let preview {
                    LabeledContent(kind == .purchase || kind == .supplierPayment ? "Nợ tiền hàng sau ghi" : "Nợ khách sau ghi", value: VND.string(kind == .purchase || kind == .supplierPayment ? preview.after.goodsPayable : preview.after.receivable))
                } else if customerID != nil && parsedAmount != nil {
                    Text(validationMessage).font(.caption).foregroundStyle(.red)
                }
                Toggle("Tôi đã kiểm tra và xác nhận", isOn: $confirmed).accessibilityIdentifier("transaction.confirmed")
            }
            ErrorMessage()
        }.scrollDismissesKeyboard(.interactively)
            .navigationTitle(original == nil ? "Ghi giao dịch" : "Điều chỉnh giao dịch")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ghi sổ") { Task { await save() } }.disabled(!confirmed || preview == nil || model.busy || original != nil && reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("transaction.save") }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Xong") { moneyFocus = nil }.accessibilityIdentifier("transaction.done") }
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
            .onChange(of: paid) { _, _ in confirmed = false }
            .onChange(of: goods) { _, _ in confirmed = false }
            .onChange(of: customerID) { _, _ in confirmed = false }
            .onChange(of: kind) { _, _ in confirmed = false }
            .onChange(of: effectiveDate) { _, _ in confirmed = false }
    }
    private var validationMessage: String {
        do { _ = try proposal(); return "" } catch { return error.localizedDescription }
    }
    private func proposal() throws -> TransactionProposal {
        guard let customerID, let amount = parsedAmount else { throw LedgerError.invalid("Chọn khách và nhập số tiền.") }
        guard let paidNow = paidAmount else { throw LedgerError.invalid("Kiểm tra số tiền đã trả.") }
        var snapshot = model.state
        if let original { snapshot.transactions.append(DebtTransaction(customerID: original.customerID, amount: original.amount, kind: .reversal, reversalOf: original.id)) }
        return try TransactionProposal(snapshot: snapshot, customerID: customerID, kind: kind, amount: amount,
                                       paidNow: kind == .purchase && original == nil ? paidNow : 0, goods: goods,
                                       date: effectiveDate, note: note, source: source, attachments: original?.attachmentIDs ?? attachments.map(\.id))
    }
    private func save() async {
        guard let ledger = model.ledger else { return }
        do {
            let proposal = try proposal()
            let success = await model.perform {
                if let original { try await ledger.correct(original.id, replacement: proposal.entries[0], reason: reason) }
                else { try await ledger.confirm(proposal, attachments: attachments, confirmed: confirmed) }
            }
            if success { onSaved?(); dismiss() }
        } catch { model.error = error.localizedDescription }
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
            Section {
                TransactionRow(entry: entry)
                if let goods = entry.goodsDescription { LabeledContent("Mặt hàng", value: goods) }
                if !entry.note.isEmpty { DisclosureGroup("Nội dung gốc") { Text(entry.note).textSelection(.enabled) } }
            }
            if !entry.attachmentIDs.isEmpty {
                Section("Chứng từ") {
                    ForEach(model.state.attachments.filter { entry.attachmentIDs.contains($0.id) }) { attachment in
                        if let image = UIImage(data: attachment.data) { Image(uiImage: image).resizable().scaledToFit().accessibilityLabel("Ảnh chứng từ") }
                    }
                }
            }
            if reversed { Label("Đã hoàn tác", systemImage: "arrow.uturn.backward") }
            else if entry.kind != .reversal {
                Section {
                    Button("Điều chỉnh giao dịch") { editing = true }
                    TextField("Lý do hoàn tác", text: $reason)
                    Button("Hoàn tác giao dịch", role: .destructive) { confirmReverse = true }.disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy)
                }
            }
            NavigationLink("Nhật ký giao dịch") { AuditLogView(entityID: entry.id) }
            ErrorMessage()
        }.navigationTitle("Chi tiết giao dịch")
            .sheet(isPresented: $editing) { NavigationStack { TransactionEditorView(original: entry) } }
            .confirmationDialog("Hoàn tác \(VND.string(entry.amount))?", isPresented: $confirmReverse, titleVisibility: .visible) {
                Button("Xác nhận hoàn tác", role: .destructive) { Task {
                    guard let ledger = model.ledger else { return }
                    _ = await model.perform { try await ledger.reverse(entry.id, reason: reason) }
                } }
            }
    }
}
