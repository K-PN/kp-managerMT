import Foundation

public struct OCRReviewSummary {
    public var debt: Int64
    public var collections: Int64
    public var customerIDs: [UUID]
    public init(rows: [OCRRow]) throws {
        debt = try CheckedMoney.sum(rows.filter { $0.kind.increasesReceivable }.compactMap(\.amount))
        collections = try CheckedMoney.sum(rows.filter { $0.kind == .collection }.compactMap(\.amount))
        customerIDs = Array(Set(rows.compactMap(\.customerID))).sorted { $0.uuidString < $1.uuidString }
    }
    public static func projectedReceivable(existing: [DebtTransaction], rows: [OCRRow]) throws -> Int64 {
        try LedgerCalculator.balance(existing + rows.map { try $0.transaction() }).receivable
    }
}
