import Foundation
import UserNotifications
import SoNoCore

actor LocalReminderService: ReminderService {
    func synchronize(snapshot: LedgerSnapshot) async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        var due: [(Customer, OpenDebt)] = []
        let index = try LedgerIndex(snapshot: snapshot)
        for customer in snapshot.customers where customer.mergedInto == nil {
            let balance = try LedgerCalculator.balance(index.entriesByRoot[customer.id] ?? [])
            due += balance.outstanding.filter { $0.dueDate != nil }.map { (customer, $0) }
        }
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("sono.") }.map(\.identifier))
        // Reserve room under iOS's pending notification limit. Reconciled after each ledger change.
        let calendar = VietnameseDate.calendar, now = Date()
        for (customer, debt) in due.sorted(by: { $0.1.dueDate! < $1.1.dueDate! }).prefix(28) {
            let dueDay = calendar.startOfDay(for: debt.dueDate!)
            for offset in [-1, 1] {
                guard let fire = calendar.date(byAdding: .hour, value: 9, to: calendar.date(byAdding: .day, value: offset, to: dueDay)!), fire > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = offset < 0 ? "Khoản nợ sắp đến hạn" : "Khoản nợ đã quá hạn"
                // Keep amounts and customer identities off the lock screen.
                content.body = "Mở Sổ Nợ AI để kiểm tra và tạo lời nhắc."
                content.sound = .default
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .timeZone], from: fire)
                let request = UNNotificationRequest(identifier: "sono.\(customer.id).\(debt.id).\(offset)", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
                try await center.add(request)
            }
        }
    }
    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
    }
    func disable() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("sono.") }.map(\.identifier))
    }
}
