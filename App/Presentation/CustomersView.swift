import SwiftUI
import SoNoCore

struct CustomersView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var adding = false
    @State private var book: AccountBook = .debt
    var body: some View {
        List {
            Picker("Danh sách", selection: $book) { Text("Khách nợ").tag(AccountBook.debt); Text("Xe hàng").tag(AccountBook.goods) }.pickerStyle(.segmented).accessibilityIdentifier("customers.book")
            ErrorMessage()
            ForEach(model.customers(in: book).filter { $0.matches(query) }) { customer in
                NavigationLink { CustomerDetailView(customerID: customer.id, account: book) } label: {
                    HStack {
                        VStack(alignment: .leading) { Text(customer.name).font(.headline); Text([customer.nickname, customer.phone].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Text(VND.string(book == .goods ? model.balance(for: customer.id).goodsPayable : model.balance(for: customer.id).receivable)).monospacedDigit().font(.subheadline.bold())
                    }.padding(.vertical, 6)
                }
            }
        }.overlay { if model.customers.isEmpty { ContentUnavailableView("Chưa có khách hàng", systemImage: "person.2", description: Text("Bấm + để thêm người đầu tiên.")) } }
            .searchable(text: $query, prompt: "Tên, biệt danh, điện thoại — có hoặc không dấu")
            .navigationTitle("Khách hàng")
            .toolbar { Button { adding = true } label: { Label("Thêm khách hàng", systemImage: "plus") }.accessibilityIdentifier("customer.add") }
            .sheet(isPresented: $adding) { NavigationStack { CustomerEditorView(customer: Customer(name: "", book: book)) } }
    }
}

struct CustomerEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var customer: Customer
    @State private var allowDuplicate = false
    init(customer: Customer = Customer(name: "")) {
        var value = customer; value.book = AccountBook.inferred(for: customer)
        _customer = State(initialValue: value)
    }
    private var hasDuplicate: Bool {
        let book = AccountBook.inferred(for: customer)
        if let original = model.state.customers.first(where: { $0.id == customer.id }), TextKey.normalize(original.name) == TextKey.normalize(customer.name), model.book(for: original) == book { return false }
        return model.customers(in: book).contains { $0.id != customer.id && TextKey.normalize($0.name) == TextKey.normalize(customer.name) }
    }
    var body: some View {
        Form {
            Section("Thông tin khách hàng") {
                Picker("Nhóm hồ sơ", selection: $customer.book) { Text("Khách nợ").tag(Optional(AccountBook.debt)); Text("Xe / nhà cung cấp").tag(Optional(AccountBook.goods)) }.accessibilityIdentifier("customer.book")
                TextField("Họ và tên", text: $customer.name).textContentType(.name).autocorrectionDisabled().accessibilityIdentifier("customer.name")
                TextField("Biệt danh", text: $customer.nickname).autocorrectionDisabled()
                TextField("Số điện thoại", text: $customer.phone).keyboardType(.phonePad)
                TextField("Địa chỉ", text: $customer.address)
            }
            if hasDuplicate {
                Section { Label("Tên này đã có trong sổ. Kiểm tra điện thoại hoặc biệt danh.", systemImage: "person.2.badge.gearshape"); Toggle("Tôi xác nhận đây là một khách khác", isOn: $allowDuplicate) }
            }
            ErrorMessage()
        }.navigationTitle("Thông tin khách")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Lưu") { Task {
                    guard let ledger = model.ledger else { return }
                    if await model.perform({ try await ledger.saveCustomer(customer, allowDuplicate: allowDuplicate) }) { dismiss() }
                } }.disabled(customer.name.trimmingCharacters(in: .whitespaces).isEmpty || model.busy || (hasDuplicate && !allowDuplicate)).accessibilityIdentifier("customer.save") }
            }
    }
}

struct CustomerDetailView: View {
    @EnvironmentObject private var model: AppModel
    var customerID: UUID
    var account: AccountBook? = nil
    @State private var edit = false
    @State private var add = false
    @State private var mergeTarget: UUID?
    @State private var mergeConfirm = false
    @State private var exported: URL?
    private var customer: Customer? { model.state.customers.first { $0.id == customerID } }
    private var book: AccountBook { account ?? customer.map { model.book(for: $0) } ?? .debt }
    private var editableCustomer: Customer? {
        guard var value = customer else { return nil }
        value.book = model.book(for: value); return value
    }
    private var entries: [DebtTransaction] { model.entries(for: customerID).filter { book.contains($0, in: model.state.transactions) } }
    var body: some View {
        List {
            if let customer {
                Section("Số dư hiện tại") {
                    if book == .debt {
                    LabeledContent("Phải thu", value: VND.string(model.balance(for: customerID).receivable))
                        .accessibilityElement(children: .combine).accessibilityIdentifier("customer.receivable")
                    } else {
                    LabeledContent("Nợ tiền hàng", value: VND.string(model.balance(for: customerID).goodsPayable)).accessibilityIdentifier("customer.goodsPayable")
                    }
                    if book == .debt && (model.balance(for: customerID).prepaid > 0 || model.balance(for: customerID).payable > model.balance(for: customerID).goodsPayable) {
                        DisclosureGroup("Số dư từ bản cũ") {
                            LabeledContent("Khoản phải trả khác", value: VND.string(model.balance(for: customerID).payable - model.balance(for: customerID).goodsPayable))
                            LabeledContent("Khách trả trước", value: VND.string(model.balance(for: customerID).prepaid))
                        }
                    }
                }
                Section("Liên hệ") {
                    if !customer.nickname.isEmpty { LabeledContent("Biệt danh", value: customer.nickname) }
                    if !customer.phone.isEmpty { LabeledContent("Điện thoại", value: customer.phone) }
                    if !customer.address.isEmpty { Text(customer.address) }
                    if !customer.note.isEmpty { DisclosureGroup("Thông tin thêm") { Text(customer.note) } }
                    ShareLink(item: reminderText(customer)) { Label("Chia sẻ lời nhắc công nợ", systemImage: "square.and.arrow.up") }
                    Button("Tạo phiếu xác nhận PDF") {
                        let entries = self.entries, balance = model.balance(for: customerID), book = self.book
                        Task {
                            do { exported = try await Task.detached { try PDFReports.statement(customer: customer, entries: entries, balance: balance, book: book) }.value }
                            catch { model.error = error.localizedDescription }
                        }
                    }
                    if let exported { ShareLink("Chia sẻ phiếu PDF", item: exported) }
                }
                Section("Lịch sử") {
                    ForEach(entries.sorted { $0.effectiveDate > $1.effectiveDate }) { entry in
                        NavigationLink { TransactionDetailView(entry: entry) } label: { TransactionRow(entry: entry) }
                    }
                }
                Section("Gộp hồ sơ") {
                    Picker("Gộp khách này vào", selection: $mergeTarget) {
                        Text("Chọn khách đích").tag(nil as UUID?)
                        ForEach(model.customers(in: book).filter { $0.id != customerID }) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Button("Kiểm tra và gộp") { mergeConfirm = true }.disabled(mergeTarget == nil || model.busy)
                }
            }
            ErrorMessage()
        }.navigationTitle(customer?.name ?? "Khách hàng")
            .toolbar {
                Button("Sửa") { edit = true }
                Button { add = true } label: { Label("Ghi giao dịch", systemImage: "plus") }.accessibilityIdentifier("customer.newTransaction")
            }
            .sheet(isPresented: $edit) { if let customer = editableCustomer { NavigationStack { CustomerEditorView(customer: customer) } } }
            .sheet(isPresented: $add) { NavigationStack { TransactionEditorView(customerID: customerID, kind: book == .goods ? .purchase : .debt) } }
            .confirmationDialog("Gộp \(customer?.name ?? "") vào \(mergeTarget.map(model.customerName) ?? "")?", isPresented: $mergeConfirm, titleVisibility: .visible) {
                Button("Xác nhận gộp", role: .destructive) { Task {
                    guard let ledger = model.ledger, let mergeTarget else { return }
                    _ = await model.perform { try await ledger.mergeCustomer(customerID, into: mergeTarget, confirmed: true) }
                } }
            }
    }
    private func reminderText(_ customer: Customer) -> String { "Chào \(customer.name), \(book == .goods ? "nợ tiền hàng" : "nợ khách") hiện tại là \(VND.string(book == .goods ? model.balance(for: customerID).goodsPayable : model.balance(for: customerID).receivable)). Anh/chị vui lòng đối chiếu và phản hồi giúp tôi. Xin cảm ơn!" }
}
