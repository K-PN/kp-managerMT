import SwiftUI
import SoNoCore

struct VoiceInputView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var speech = AppleVoiceRecognition()
    @State private var text = ""
    @State private var reviewText = ""
    @State private var draft: VoiceDraft?
    @State private var intent: VoiceIntent = .unknown
    @State private var selectedCustomerID: UUID?
    @State private var creatingNew = false
    @State private var newName = ""
    @State private var pendingCustomerID = UUID()
    @State private var editingDetails = false
    @State private var amount = ""
    @State private var paid = "0"
    @State private var goods = ""
    @State private var date = Date()
    @State private var answer: String?
    @State private var processing = false
    @State private var starting = false
    @State private var started = false
    @State private var loaded = false
    @State private var completed = false
    @State private var saving = false
    private enum MoneyField: Hashable { case amount, paid }
    @FocusState private var editingMoney: MoneyField?
    @FocusState private var editingTranscript: Bool
    private var currentReview: Bool { draft != nil && reviewText == text && !speech.recording && !processing }
    private var query: Bool { [.balance, .supplierBalance, .todayCollections, .overdue].contains(intent) }
    private var book: AccountBook { [.purchase, .supplierPayment, .supplierBalance].contains(intent) ? .goods : .debt }
    private var pendingCustomer: Customer? { creatingNew ? Customer(id: pendingCustomerID, name: newName, book: book) : nil }
    private var customerChoice: Binding<UUID?> {
        Binding(get: { creatingNew ? pendingCustomerID : selectedCustomerID }, set: { value in
            creatingNew = value == pendingCustomerID
            selectedCustomerID = creatingNew ? nil : value
        })
    }
    private var actionKind: TransactionKind? {
        switch intent {
        case .debt: return .debt
        case .collection: return .collection
        case .purchase: return .purchase
        case .supplierPayment: return .supplierPayment
        default: return nil
        }
    }
    private var paidAmount: Int64? { paid == "0" ? 0 : VietnameseMoneyParser().parse(paid).amount }
    private var proposal: TransactionProposal? { try? makeProposal() }
    private var canConfirm: Bool {
        guard currentReview, !completed, !saving, !model.busy else { return false }
        return intent == .createCustomer ? !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : proposal != nil
    }
    var body: some View {
        Form {
            if !currentReview && !completed { microphone }
            Section("Văn bản vừa nói") {
                TextEditor(text: $text).frame(minHeight: 95).accessibilityLabel("Nội dung lời nói").accessibilityIdentifier("voice.transcript")
                    .focused($editingTranscript).autocorrectionDisabled()
                    .disabled(speech.recording || processing || starting || saving)
                if !speech.recording && !processing && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(currentReview ? "Phân tích lại" : "Xem kết quả") { analyze() }.accessibilityIdentifier("voice.analyze")
                    if currentReview { Button("Nói lại") { Task { await startSpeaking() } }.accessibilityIdentifier("voice.mic") }
                }
            }
            if currentReview && !completed {
                selection
                if intent == .createCustomer {
                    Section("Khách mới") {
                        Text(newName.isEmpty ? "Nhập tên khách để tiếp tục" : newName).font(.headline)
                        Text("Chưa lưu vào danh sách").font(.caption).foregroundStyle(.secondary)
                        confirmButton
                    }
                } else if query {
                    Section("Kết quả tra cứu") { Text(answer ?? "Chọn khách để tra cứu.").textSelection(.enabled) }
                } else {
                    comparison
                }
            }
            if completed {
                Section { Label("Đã xác nhận và lưu", systemImage: "checkmark.circle.fill").foregroundStyle(.teal).accessibilityIdentifier("voice.saved") }
            }
            if let error = speech.error { Text(error).font(.caption).foregroundStyle(.red) }
            ErrorMessage()
        }.navigationTitle("Nói để ghi sổ").navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Xong") { editingMoney = nil; editingTranscript = false }.accessibilityIdentifier("voice.done") }
            }
            .task {
                guard !loaded else { return }; loaded = true
                if !model.suppressSpeechForUITests { await startSpeaking() }
            }
            .onChange(of: speech.transcript) { _, value in if !completed { text = value } }
            .onChange(of: speech.recording) { previous, recording in
                if previous && !recording && !processing && started { Task { await finishSpeaking() } }
            }
            .onChange(of: selectedCustomerID) { _, _ in if query { updateAnswer() } }
            .onChange(of: intent) { _, value in
                if value == .createCustomer { creatingNew = true }
                if let id = selectedCustomerID, !model.customers(in: book).contains(where: { $0.id == id }) { selectedCustomerID = nil }
                if query { creatingNew = false; updateAnswer() }
            }
            .onDisappear { started = false; speech.cancel() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { started = false; speech.cancel() } }
    }
    private var microphone: some View {
        Section {
            VStack(spacing: 16) {
                Text(starting ? "Đang mở micro…" : processing ? "Đang xử lý…" : speech.recording ? "Đang nói" : "Nói lại")
                    .font(.title3.bold()).accessibilityIdentifier("voice.status")
                Button {
                    Task { if speech.recording { await finishSpeaking() } else { await startSpeaking() } }
                } label: {
                    Image(systemName: speech.recording ? "mic.fill" : "mic")
                        .font(.system(size: 34, weight: .medium)).foregroundStyle(.white)
                        .frame(width: 88, height: 88)
                        .background(speech.recording ? Color.orange : Color.teal, in: Circle())
                        .overlay { Circle().stroke((speech.recording ? Color.orange : Color.teal).opacity(0.16), lineWidth: 12) }
                }.buttonStyle(.plain).disabled(starting || processing || saving)
                    .accessibilityLabel(speech.recording ? "Dừng và xử lý" : "Nói lại").accessibilityIdentifier("voice.mic")
                SpeechRhythm(level: speech.level, recording: speech.recording).frame(height: 36)
            }.frame(maxWidth: .infinity).padding(.vertical, 14)
        }.listRowBackground(Color.clear)
    }
    private var selection: some View {
        Section("Kết quả tạm thời") {
            if ![.createCustomer, .todayCollections, .overdue].contains(intent) {
            Picker("Thao tác", selection: $intent) {
                if intent == .unknown { Text("Chọn thao tác").tag(VoiceIntent.unknown) }
                Text("Ghi nợ").tag(VoiceIntent.debt)
                Text("Thu nợ").tag(VoiceIntent.collection)
                Text("Nợ tiền hàng").tag(VoiceIntent.purchase)
                Text("Trả tiền hàng").tag(VoiceIntent.supplierPayment)
                Text("Tra cứu khách nợ").tag(VoiceIntent.balance)
                Text("Tra cứu nợ xe").tag(VoiceIntent.supplierBalance)
            }.accessibilityIdentifier("voice.intent")
            }
            if intent != .todayCollections && intent != .overdue {
                Picker(book == .goods ? "Xe / nhà cung cấp" : "Khách nợ", selection: customerChoice) {
                    Text("Chọn đúng người").tag(nil as UUID?)
                    if !query && !newName.isEmpty { Text(newName + " · mới").tag(Optional(pendingCustomerID)) }
                    ForEach(model.customers(in: book)) { customer in Text(customer.name).tag(Optional(customer.id)) }
                }.accessibilityIdentifier("voice.customer")
                if creatingNew {
                    TextField("Tên khách mới", text: $newName).autocorrectionDisabled().accessibilityIdentifier("voice.newName")
                }
            }
            if let draft {
                ForEach(draft.warnings.filter { $0.contains("ngày") || $0.contains("nhiều khách") }, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
            }
        }
    }
    private var transactionFields: some View {
        DisclosureGroup("Sửa chi tiết", isExpanded: $editingDetails) {
            if [.purchase, .debt, .collection].contains(intent) { TextField(intent == .purchase ? "Mặt hàng / số lượng" : "Hàng khách nợ / số lượng", text: $goods, axis: .vertical).accessibilityIdentifier("voice.goods") }
            TextField(intent == .purchase ? "Tổng tiền hàng (đồng)" : intent == .debt ? "Số tiền nợ (đồng)" : "Số tiền (đồng)", text: $amount).keyboardType(.numberPad).focused($editingMoney, equals: .amount).accessibilityIdentifier("voice.amount")
            if let value = VietnameseMoneyParser().parse(amount).amount { Text(VND.string(value)).font(.title2.bold()).foregroundStyle(.teal).accessibilityIdentifier("voice.amountVND") }
            if intent == .purchase { TextField("Đã trả (đồng)", text: $paid).keyboardType(.numberPad).focused($editingMoney, equals: .paid).accessibilityIdentifier("voice.paid") }
            DatePicker("Ngày giao dịch", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
        }.accessibilityIdentifier("voice.editDetails")
    }
    private var comparison: some View {
        Section("Đối chiếu trước khi xác nhận") {
            if let proposal {
                if let entry = proposal.entries.first {
                    VoiceAmountSummary(action: entry.kind.title, goods: goods, amount: entry.amount)
                        .accessibilityIdentifier("voice.summary")
                }
                if book == .debt {
                    LabeledContent("Nợ khách cũ", value: VND.string(proposal.before.receivable)).accessibilityIdentifier("voice.oldDebt")
                } else { LabeledContent("Nợ tiền hàng cũ", value: VND.string(proposal.before.goodsPayable)) }
                if intent == .purchase, let paidAmount, paidAmount > 0 { LabeledContent("Đã trả lần này", value: VND.string(paidAmount)) }
                if book == .debt {
                    LabeledContent("Nợ khách sau ghi", value: VND.string(proposal.after.receivable)).accessibilityIdentifier("voice.newDebt")
                } else { LabeledContent("Nợ tiền hàng sau ghi", value: VND.string(proposal.after.goodsPayable)).accessibilityIdentifier("voice.newGoodsDebt") }
            } else {
                Text(validationMessage).font(.caption).foregroundStyle(.red)
            }
            transactionFields
            confirmButton
        }
    }
    private var confirmButton: some View {
        Button { Task { await confirm() } } label: { Text(saving ? "Đang lưu…" : "Xác nhận").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8) }
            .buttonStyle(.borderedProminent)
            .disabled(!canConfirm)
            .accessibilityIdentifier("voice.confirm")
    }
    private var validationMessage: String {
        do { _ = try makeProposal(); return "" } catch { return error.localizedDescription }
    }
    private func makeProposal() throws -> TransactionProposal {
        guard let actionKind, let value = VietnameseMoneyParser().parse(amount).amount else { throw LedgerError.invalid("Chọn thao tác và nhập số tiền rõ ràng.") }
        let customer = pendingCustomer
        guard let id = customer?.id ?? selectedCustomerID else { throw LedgerError.invalid("Chọn đúng khách hoặc thêm người mới.") }
        guard let paidAmount else { throw LedgerError.invalid("Kiểm tra phần đã trả.") }
        return try TransactionProposal(snapshot: model.state, customerID: id, kind: actionKind, amount: value,
                                       paidNow: intent == .purchase ? paidAmount : 0, goods: goods, date: date,
                                       note: text, source: .voice, newCustomer: customer)
    }
    private func startSpeaking() async {
        starting = true; completed = false; draft = nil; answer = nil; started = false
        defer { starting = false }
        do { try await speech.start(allowAppleServer: true); started = true; text = "" }
        catch is CancellationError { }
        catch { model.error = error.localizedDescription }
    }
    private func finishSpeaking() async {
        guard !processing else { return }; processing = true
        text = await speech.finish(); speech.cancel(); started = false; processing = false
        guard !Task.isCancelled else { return }
        analyze()
    }
    private func analyze() {
        editingMoney = nil; editingTranscript = false
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { model.error = "Chưa nghe rõ. Bạn có thể nói lại hoặc nhập văn bản."; return }
        let parsed = VietnameseVoiceParser().parse(text, customers: model.voiceCustomers, now: Date())
        draft = parsed; reviewText = text; intent = parsed.intent; date = parsed.effectiveDate; completed = false
        pendingCustomerID = UUID()
        editingDetails = parsed.amount == nil || parsed.warnings.contains { $0.contains("ngày") }
        selectedCustomerID = parsed.candidateIDs.count == 1 ? parsed.candidateIDs.first : nil
        creatingNew = parsed.newCustomerName != nil || intent == .createCustomer
        newName = parsed.newCustomerName ?? ""; amount = parsed.amount.map(String.init) ?? ""
        paid = String(parsed.paidNow ?? 0); goods = parsed.goodsDescription ?? ""
        answer = nil
        if query { creatingNew = false; updateAnswer() }
    }
    private func updateAnswer() {
        guard var draft else { return }; draft.intent = intent
        do { answer = try model.answer(for: draft, selectedCustomerID: selectedCustomerID) }
        catch { answer = error.localizedDescription }
    }
    private func confirm() async {
        guard !saving, !completed, currentReview, let ledger = model.ledger else { return }
        saving = true; defer { saving = false }
        do {
            let success: Bool
            if intent == .createCustomer {
                let customer = Customer(name: newName)
                success = await model.perform { try await ledger.saveCustomer(customer) }
            } else {
                let proposal = try makeProposal()
                success = await model.perform { try await ledger.confirm(proposal, confirmed: true) }
            }
            if success { completed = true; draft = nil; speech.cancel() }
        } catch { model.error = error.localizedDescription }
    }
}

private struct VoiceAmountSummary: View {
    let action: String
    let goods: String
    let amount: Int64
    private var item: String { goods.isEmpty ? action : goods }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !goods.isEmpty { Text(action).font(.caption).foregroundStyle(.secondary) }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item).fixedSize()
                    Spacer(minLength: 12)
                    Text(VND.string(amount)).bold().monospacedDigit().fixedSize()
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(item).fixedSize(horizontal: false, vertical: true)
                    Text(VND.string(amount)).bold().monospacedDigit().fixedSize(horizontal: false, vertical: true)
                }
            }
        }.accessibilityElement(children: .combine)
    }
}

private struct SpeechRhythm: View {
    let level: Double
    let recording: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08, paused: !recording)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<19, id: \.self) { index in
                    let shape = 0.35 + 0.65 * abs(sin(time * 5 + Double(index) * 0.65))
                    Capsule().fill(recording ? Color.teal : Color.secondary.opacity(0.3))
                        .frame(width: 4, height: 4 + (recording ? level * 32 * shape : 0))
                }
            }.frame(maxWidth: .infinity)
        }.accessibilityHidden(true)
    }
}
