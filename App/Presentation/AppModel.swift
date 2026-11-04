import SwiftUI
import LocalAuthentication
import SoNoCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state = LedgerSnapshot()
    @Published private(set) var summary: DashboardSummary?
    @Published private(set) var ledger: LedgerService?
    @Published var error: String?
    @Published var isLoading = true
    @Published var locked = false
    @Published var busy = false
    var backup: LocalBackupService?
    let reminders = LocalReminderService()
    var customers: [Customer] { state.customers.filter { $0.mergedInto == nil }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    var suppressSpeechForUITests: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["SONO_UI_TEST_STORE"].flatMap(UUID.init(uuidString:)) != nil && ProcessInfo.processInfo.environment["SONO_UI_TEST_SPEECH"] == "1"
        #else
        return false
        #endif
    }
    func open() async {
        guard ledger == nil else { return }
        do {
            let service = try await Task.detached(priority: .userInitiated) {
                let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                var folder = support.appendingPathComponent("SoNoAI", isDirectory: true)
                #if DEBUG && targetEnvironment(simulator)
                // UI tests get an empty isolated ledger; release builds cannot select another store.
                if let value = ProcessInfo.processInfo.environment["SONO_UI_TEST_STORE"], let id = UUID(uuidString: value) {
                    folder = support.appendingPathComponent("SoNoAI-UITests", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true)
                }
                #endif
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
                return try LedgerService(databaseURL: folder.appendingPathComponent("ledger.sqlite"))
            }.value
            ledger = service; backup = LocalBackupService(ledger: service)
            locked = UserDefaults.standard.bool(forKey: "appLock")
            if !locked { await refresh() }
        } catch { self.error = error.localizedDescription }
        isLoading = false
    }
    func refresh() async {
        guard let ledger else { return }
        do {
            let snapshot = try await ledger.snapshot()
            let totals = try await Task.detached { try DashboardSummary(snapshot: snapshot) }.value
            state = snapshot; summary = totals
            // This version no longer schedules debt deadlines. Clear old pending reminders.
            if UserDefaults.standard.bool(forKey: "remindersEnabled") { await reminders.disable(); UserDefaults.standard.set(false, forKey: "remindersEnabled") }
        } catch { self.error = error.localizedDescription }
    }
    @discardableResult
    func perform(_ action: () async throws -> Void) async -> Bool {
        guard !busy else { return false }; busy = true; defer { busy = false }
        do { try await action(); await refresh(); return true }
        catch { self.error = error.localizedDescription; return false }
    }
    func customerName(_ id: UUID) -> String { state.customers.first { $0.id == id }?.name ?? "Khách hàng" }
    func entries(for id: UUID) -> [DebtTransaction] { (try? state.entries(for: id)) ?? [] }
    func balance(for id: UUID) -> Balance {
        if let value = summary?.balances[id] { return value }
        return summary?.balances[(try? state.rootID(id)) ?? id] ?? Balance()
    }
    func answer(for draft: VoiceDraft, selectedCustomerID: UUID?) throws -> String {
        switch draft.intent {
        case .balance:
            guard let id = selectedCustomerID else { throw LedgerError.invalid("Hãy chọn một khách hàng để tra cứu.") }
            return "\(customerName(id))\nNợ khách: \(VND.string(balance(for: id).receivable))\nNợ tiền hàng: \(VND.string(balance(for: id).goodsPayable))"
        case .todayCollections:
            let entries = try LedgerCalculator.active(state.transactions).filter { $0.kind == .collection && VietnameseDate.calendar.isDateInToday($0.effectiveDate) }
            return "Đã thu hôm nay: \(VND.string(summary?.collectedToday ?? 0)). " + entries.map { "\(customerName($0.customerID)): \(VND.string($0.amount))" }.joined(separator: "; ")
        case .overdue:
            let today = VietnameseDate.calendar.startOfDay(for: Date())
            let names = try customers.compactMap { customer -> String? in
                let overdue = try CheckedMoney.sum(balance(for: customer.id).outstanding.filter { $0.dueDate.map { $0 < today } ?? false }.map(\.amount))
                return overdue > 0 ? "\(customer.name): \(VND.string(overdue))" : nil
            }
            return names.isEmpty ? "Không có khoản phải thu quá hạn." : names.joined(separator: "\n")
        default: throw LedgerError.invalid("Đây là yêu cầu ghi giao dịch. Hãy kiểm tra bản nháp.")
        }
    }
    func lockIfEnabled() {
        if UserDefaults.standard.bool(forKey: "appLock") { locked = true }
    }
    func unlock() async {
        let context = LAContext()
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Mở sổ công nợ của bạn")
            if success { locked = false; await refresh() }
        } catch { self.error = "Chưa mở khóa: \(error.localizedDescription)" }
    }
}

enum VND {
    static func string(_ amount: Int64) -> String {
        let formatter = NumberFormatter(); formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "vi_VN"); formatter.currencyCode = "VND"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount) ₫"
    }
}
