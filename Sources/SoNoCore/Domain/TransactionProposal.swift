import Foundation

/// A preview is pure calculation. Only LedgerService.confirm writes it atomically.
public struct TransactionProposal: Sendable {
    public let entries: [DebtTransaction]
    public let newCustomer: Customer?
    public let before: Balance
    public let after: Balance
    public init(snapshot: LedgerSnapshot, customerID: UUID, kind: TransactionKind, amount: Int64,
                paidNow: Int64 = 0, goods: String = "", date: Date = Date(), note: String = "",
                source: EntrySource = .manual, newCustomer: Customer? = nil, attachments: [UUID] = []) throws {
        guard amount > 0, kind != .reversal, paidNow >= 0, paidNow <= amount else { throw LedgerError.invalid("Kiểm tra tổng tiền và số tiền đã trả.") }
        if let newCustomer {
            guard newCustomer.id == customerID, !newCustomer.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LedgerError.invalid("Cần tên khách mới.") }
        }
        let old = newCustomer == nil ? try snapshot.entries(for: customerID) : []
        before = try LedgerCalculator.balance(old)
        let description = goods.trimmingCharacters(in: .whitespacesAndNewlines)
        guard kind != .purchase || !description.isEmpty else { throw LedgerError.invalid("Hãy nhập mặt hàng đã lấy.") }
        let entry = DebtTransaction(customerID: customerID, amount: amount, kind: kind, effectiveDate: date,
                                    note: note, source: source, attachmentIDs: attachments,
                                    goodsDescription: [.debt, .collection, .purchase].contains(kind) && !description.isEmpty ? description : nil)
        var pending = [entry]
        if kind == .purchase && paidNow > 0 {
            pending.append(DebtTransaction(customerID: customerID, amount: paidNow, kind: .supplierPayment,
                                          effectiveDate: date, source: source, now: entry.createdAt.addingTimeInterval(0.001), relatedPurchaseID: entry.id))
        }
        after = try LedgerCalculator.balance(old + pending)
        self.entries = pending; self.newCustomer = newCustomer
    }
}

public enum LedgerDateRange {
    public static func contains(_ date: Date, from start: Date, through end: Date) -> Bool {
        let calendar = VietnameseDate.calendar
        let lower = calendar.startOfDay(for: start), upper = calendar.startOfDay(for: end)
        guard lower <= upper, let exclusiveEnd = calendar.date(byAdding: .day, value: 1, to: upper) else { return false }
        return date >= lower && date < exclusiveEnd
    }
}
