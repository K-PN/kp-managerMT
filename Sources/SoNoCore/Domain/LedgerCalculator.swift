import Foundation

public struct OpenDebt: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var amount: Int64
    public var dueDate: Date?
}
public struct Balance: Equatable, Sendable {
    public var receivable: Int64 = 0
    public var payable: Int64 = 0
    public var prepaid: Int64 = 0
    public var outstanding: [OpenDebt] = []
    public init() {}
}
public enum CheckedMoney {
    public static func add(_ a: Int64, _ b: Int64) throws -> Int64 {
        let (value, overflow) = a.addingReportingOverflow(b)
        guard !overflow else { throw LedgerError.overflow }; return value
    }
    public static func multiply(_ a: Int64, _ b: Int64) throws -> Int64 {
        let (value, overflow) = a.multipliedReportingOverflow(by: b)
        guard !overflow else { throw LedgerError.overflow }; return value
    }
    public static func sum(_ values: [Int64]) throws -> Int64 { try values.reduce(0, add) }
}
public enum LedgerCalculator {
    public static func active(_ entries: [DebtTransaction]) throws -> [DebtTransaction] {
        guard Set(entries.map(\.id)).count == entries.count else { throw LedgerError.invalid("UUID giao dịch trùng.") }
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        var reversed = Set<UUID>()
        for entry in entries {
            guard entry.amount > 0 else { throw LedgerError.invalid("Số tiền phải lớn hơn 0.") }
            if entry.kind == .reversal {
                guard let originalID = entry.reversalOf, let original = byID[originalID],
                      original.kind != .reversal, original.customerID == entry.customerID,
                      original.amount == entry.amount, reversed.insert(originalID).inserted else {
                    throw LedgerError.invalid("Giao dịch hoàn tác không hợp lệ hoặc đã hoàn tác.")
                }
            } else if entry.reversalOf != nil { throw LedgerError.invalid("Liên kết hoàn tác không hợp lệ.") }
        }
        return entries.filter { $0.kind != .reversal && !reversed.contains($0.id) }.sorted {
            if $0.effectiveDate != $1.effectiveDate { return $0.effectiveDate < $1.effectiveDate }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
    /// Apply payments FIFO by effective date, then creation time and UUID. No floating point money.
    public static func balance(_ entries: [DebtTransaction]) throws -> Balance {
        var result = Balance()
        for entry in try active(entries) {
            switch entry.kind {
            case .debt, .loan, .adjustmentIncrease:
                result.receivable = try CheckedMoney.add(result.receivable, entry.amount)
                result.outstanding.append(OpenDebt(id: entry.id, amount: entry.amount, dueDate: entry.dueDate))
            case .collection, .adjustmentDecrease, .advanceUsed:
                guard entry.amount <= result.receivable else { throw LedgerError.overpayment }
                if entry.kind == .advanceUsed {
                    guard entry.amount <= result.prepaid else { throw LedgerError.overpayment }
                    result.prepaid -= entry.amount
                }
                result.receivable -= entry.amount
                var remaining = entry.amount
                for index in result.outstanding.indices where remaining > 0 {
                    let applied = min(result.outstanding[index].amount, remaining)
                    result.outstanding[index].amount -= applied; remaining -= applied
                }
            case .borrowing: result.payable = try CheckedMoney.add(result.payable, entry.amount)
            case .repayment:
                guard entry.amount <= result.payable else { throw LedgerError.overpayment }
                result.payable -= entry.amount
            case .advanceReceived: result.prepaid = try CheckedMoney.add(result.prepaid, entry.amount)
            case .reversal: break
            }
        }
        result.outstanding.removeAll { $0.amount == 0 }
        return result
    }
}

public struct DashboardSummary: Sendable {
    public var receivable: Int64 = 0
    public var payable: Int64 = 0
    public var prepaid: Int64 = 0
    public var collectedToday: Int64 = 0
    public var collectedThisMonth: Int64 = 0
    public var overdue: Int64 = 0
    public var customerCount: Int = 0
    public var balances: [UUID: Balance] = [:]
    public init(snapshot: LedgerSnapshot, now: Date = Date()) throws {
        let calendar = VietnameseDate.calendar
        let today = calendar.startOfDay(for: now)
        let month = calendar.dateInterval(of: .month, for: now)!
        let activeCustomers = snapshot.customers.filter { $0.mergedInto == nil }
        let index = try LedgerIndex(snapshot: snapshot)
        customerCount = activeCustomers.count
        for customer in activeCustomers {
            let entries = index.entriesByRoot[customer.id] ?? []
            let balance = try LedgerCalculator.balance(entries)
            balances[customer.id] = balance
            receivable = try CheckedMoney.add(receivable, balance.receivable)
            payable = try CheckedMoney.add(payable, balance.payable)
            prepaid = try CheckedMoney.add(prepaid, balance.prepaid)
            overdue = try CheckedMoney.add(overdue, CheckedMoney.sum(balance.outstanding.filter {
                guard let due = $0.dueDate else { return false }; return due < today
            }.map(\.amount)))
            for entry in try LedgerCalculator.active(entries) where entry.kind == .collection {
                if calendar.isDate(entry.effectiveDate, inSameDayAs: now) { collectedToday = try CheckedMoney.add(collectedToday, entry.amount) }
                if entry.effectiveDate >= month.start && entry.effectiveDate < month.end && entry.effectiveDate <= now {
                    collectedThisMonth = try CheckedMoney.add(collectedThisMonth, entry.amount)
                }
            }
        }
    }
}

/// Build once per projection instead of rescanning every transaction for every customer.
public struct LedgerIndex: Sendable {
    public var roots: [UUID: UUID] = [:]
    public var entriesByRoot: [UUID: [DebtTransaction]] = [:]
    public init(snapshot: LedgerSnapshot) throws {
        let customers = Dictionary(uniqueKeysWithValues: snapshot.customers.map { ($0.id, $0) })
        for customer in snapshot.customers {
            var current = customer.id, path: [UUID] = [], seen = Set<UUID>()
            while roots[current] == nil {
                guard seen.insert(current).inserted, let value = customers[current] else { throw LedgerError.invalid("Liên kết khách bị lỗi.") }
                path.append(current)
                if let target = value.mergedInto { current = target }
                else { roots[current] = current }
            }
            let root = roots[current]!
            for member in path { roots[member] = root }
        }
        for entry in snapshot.transactions {
            guard let root = roots[entry.customerID] else { throw LedgerError.notFound }
            entriesByRoot[root, default: []].append(entry)
        }
    }
}
public enum VietnameseDate {
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        calendar.locale = Locale(identifier: "vi_VN"); return calendar
    }
    public static func display(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone; formatter.locale = calendar.locale
        formatter.dateFormat = "dd/MM/yyyy HH:mm"; return formatter.string(from: date)
    }
}
