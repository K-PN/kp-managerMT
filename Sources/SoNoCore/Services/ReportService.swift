import Foundation

public enum ReportPeriod: String, CaseIterable, Sendable { case day = "Ngày", week = "Tuần", month = "Tháng" }
public struct CollectionReport: Identifiable, Sendable {
    public var id: Date
    public var total: Int64
    public var count: Int
}
public struct TradingReport: Identifiable, Sendable {
    public var id: Date
    public var purchases: Int64
    public var paid: Int64
    public var collected: Int64
}
public struct ReportTotals: Sendable {
    public var purchases: Int64 = 0
    public var paid: Int64 = 0
    public var collected: Int64 = 0
    public var receivable: Int64 = 0
    public var goodsPayable: Int64 = 0
    public init() {}
}
public enum ReportService {
    public static func trading(_ entries: [DebtTransaction], period: ReportPeriod) throws -> [TradingReport] {
        let component: Calendar.Component = period == .day ? .day : period == .week ? .weekOfYear : .month
        let grouped = Dictionary(grouping: try LedgerCalculator.active(entries).filter { [.purchase, .supplierPayment, .collection].contains($0.kind) }) {
            VietnameseDate.calendar.dateInterval(of: component, for: $0.effectiveDate)!.start
        }
        return try grouped.map { date, entries in
            TradingReport(id: date, purchases: try CheckedMoney.sum(entries.filter { $0.kind == .purchase }.map(\.amount)),
                          paid: try CheckedMoney.sum(entries.filter { $0.kind == .supplierPayment }.map(\.amount)),
                          collected: try CheckedMoney.sum(entries.filter { $0.kind == .collection }.map(\.amount)))
        }.sorted { $0.id > $1.id }
    }
    public static func totals(snapshot: LedgerSnapshot, customerID: UUID? = nil) throws -> ReportTotals {
        var filtered = snapshot
        filtered.transactions = try customerID.map { try snapshot.entries(for: $0) } ?? snapshot.transactions
        let active = try LedgerCalculator.active(filtered.transactions)
        let summary = try DashboardSummary(snapshot: filtered)
        var result = ReportTotals()
        result.purchases = try CheckedMoney.sum(active.filter { $0.kind == .purchase }.map(\.amount))
        result.paid = try CheckedMoney.sum(active.filter { $0.kind == .supplierPayment }.map(\.amount))
        result.collected = try CheckedMoney.sum(active.filter { $0.kind == .collection }.map(\.amount))
        result.receivable = summary.receivable; result.goodsPayable = summary.goodsPayable
        return result
    }
    public static func collections(_ entries: [DebtTransaction], period: ReportPeriod) throws -> [CollectionReport] {
        let calendar = VietnameseDate.calendar
        let component: Calendar.Component = period == .day ? .day : period == .week ? .weekOfYear : .month
        let active = try LedgerCalculator.active(entries).filter { $0.kind == .collection }
        let grouped = Dictionary(grouping: active) { calendar.dateInterval(of: component, for: $0.effectiveDate)!.start }
        return try grouped.map { CollectionReport(id: $0.key, total: try CheckedMoney.sum($0.value.map(\.amount)), count: $0.value.count) }.sorted { $0.id > $1.id }
    }
    public static func csv(snapshot: LedgerSnapshot, customerID: UUID? = nil) throws -> String {
        func escaped(_ text: String) -> String {
            // Neutralize spreadsheet formula injection when exporting user-provided text.
            let first = text.trimmingCharacters(in: .whitespacesAndNewlines).first
            let safe = first.map { "=+-@".contains($0) } == true ? "'" + text : text
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let entries = try customerID.map { try snapshot.entries(for: $0) } ?? snapshot.transactions
        let rows = entries.sorted { $0.effectiveDate < $1.effectiveDate }.map { entry in
            let name = snapshot.customers.first { $0.id == entry.customerID }?.name ?? ""
            return [entry.id.uuidString, name, entry.kind.title, String(entry.amount), VietnameseDate.display(entry.effectiveDate), entry.goodsDescription ?? "", entry.note, entry.reversalOf?.uuidString ?? ""].map(escaped).joined(separator: ",")
        }
        let totals = try totals(snapshot: snapshot, customerID: customerID)
        let footer: [(String, Int64)] = [("TỔNG TIỀN HÀNG", totals.purchases), ("TỔNG ĐÃ TRẢ TIỀN HÀNG", totals.paid), ("TỔNG THU NỢ", totals.collected), ("TỔNG NỢ KHÁCH", totals.receivable), ("TỔNG NỢ TIỀN HÀNG", totals.goodsPayable)]
        let totalRows = footer.map { label, amount in ["", "", label, String(amount), "", "", "", ""].map(escaped).joined(separator: ",") }
        return "\u{feff}UUID,Khách hàng / nhà cung cấp,Loại,Số tiền VND,Ngày giao dịch,Mặt hàng,Nội dung,Hoàn tác UUID\r\n" + (rows + totalRows).joined(separator: "\r\n")
    }
}
