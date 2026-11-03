import Foundation

public enum ReportPeriod: String, CaseIterable, Sendable { case day = "Ngày", week = "Tuần", month = "Tháng" }
public struct CollectionReport: Identifiable, Sendable {
    public var id: Date
    public var total: Int64
    public var count: Int
}
public enum ReportService {
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
            return [entry.id.uuidString, name, entry.kind.title, String(entry.amount), VietnameseDate.display(entry.effectiveDate), entry.dueDate.map(VietnameseDate.display) ?? "", entry.note, entry.reversalOf?.uuidString ?? ""].map(escaped).joined(separator: ",")
        }
        return "\u{feff}UUID,Khách hàng,Loại,Số tiền VND,Ngày giao dịch,Hạn trả,Ghi chú,Hoàn tác UUID\r\n" + rows.joined(separator: "\r\n")
    }
}
