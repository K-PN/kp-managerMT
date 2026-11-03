import XCTest
@testable import SoNoCore

final class FinancialCoreTests: XCTestCase {
    private let customerID = UUID()
    private let day = Date(timeIntervalSince1970: 1_600_000_000)
    private func entry(_ amount: Int64, _ kind: TransactionKind, offset: TimeInterval = 0, due: Date? = nil) -> DebtTransaction {
        DebtTransaction(customerID: customerID, amount: amount, kind: kind, effectiveDate: day.addingTimeInterval(offset), dueDate: due)
    }
    func testDebtPartialAndFullPayment() throws {
        let debt = entry(500_000, .debt)
        let partial = entry(200_000, .collection, offset: 10)
        XCTAssertEqual(try LedgerCalculator.balance([debt, partial]).receivable, 300_000)
        XCTAssertEqual(try LedgerCalculator.balance([debt, partial, entry(300_000, .collection, offset: 20)]).receivable, 0)
    }
    func testOverpaymentAndNegativeAmountsAreRejected() {
        XCTAssertThrowsError(try LedgerCalculator.balance([entry(100, .debt), entry(101, .collection, offset: 1)]))
        XCTAssertThrowsError(try LedgerCalculator.balance([entry(-1, .debt)]))
        XCTAssertThrowsError(try LedgerCalculator.balance([entry(0, .debt)]))
    }
    func testOverflowDoesNotWrap() {
        XCTAssertThrowsError(try LedgerCalculator.balance([entry(Int64.max, .debt), entry(1, .debt, offset: 1)]))
        XCTAssertThrowsError(try CheckedMoney.multiply(Int64.max, 2))
    }
    func testIndependentPayableAndPrepaidLedgers() throws {
        let entries = [entry(500, .debt), entry(400, .borrowing, offset: 1), entry(100, .repayment, offset: 2), entry(200, .advanceReceived, offset: 3), entry(150, .advanceUsed, offset: 4)]
        let balance = try LedgerCalculator.balance(entries)
        XCTAssertEqual(balance.receivable, 350); XCTAssertEqual(balance.payable, 300); XCTAssertEqual(balance.prepaid, 50)
        XCTAssertThrowsError(try LedgerCalculator.balance([entry(1, .repayment)]))
        XCTAssertThrowsError(try LedgerCalculator.balance([entry(100, .debt), entry(1, .advanceUsed, offset: 1)]))
    }
    func testFIFOAllocationAndOverdueUsesRemainingAmount() throws {
        let a = entry(500, .debt, due: day), b = entry(250, .debt, offset: 1)
        let balance = try LedgerCalculator.balance([b, entry(600, .collection, offset: 2), a])
        XCTAssertEqual(balance.outstanding, [OpenDebt(id: b.id, amount: 150, dueDate: nil)])
    }
    func testReversalRetainsOriginalButRecomputesBalance() throws {
        let debt = entry(500, .debt), collection = entry(300, .collection, offset: 1)
        let reversal = DebtTransaction(customerID: customerID, amount: 300, kind: .reversal, reversalOf: collection.id)
        XCTAssertEqual(try LedgerCalculator.balance([debt, collection, reversal]).receivable, 500)
        let debtReversal = DebtTransaction(customerID: customerID, amount: 500, kind: .reversal, reversalOf: debt.id)
        XCTAssertThrowsError(try LedgerCalculator.balance([debt, collection, debtReversal]))
        XCTAssertThrowsError(try LedgerCalculator.balance([debt, collection, reversal, reversal]))
    }
    func testReversalCannotCrossCustomers() {
        let debt = entry(500, .debt)
        let reversal = DebtTransaction(customerID: UUID(), amount: 500, kind: .reversal, reversalOf: debt.id)
        XCTAssertThrowsError(try LedgerCalculator.active([debt, reversal]))
    }
    func testEffectiveDateOrderRejectsCollectionBeforeDebt() {
        XCTAssertThrowsError(try LedgerCalculator.balance([entry(100, .debt, offset: 10), entry(1, .collection)]))
    }
    func testReportsExcludeReversedCollections() throws {
        let debt = entry(500, .debt), collection = entry(300, .collection, offset: 1)
        let reversal = DebtTransaction(customerID: customerID, amount: 300, kind: .reversal, reversalOf: collection.id)
        XCTAssertTrue(try ReportService.collections([debt, collection, reversal], period: .month).isEmpty)
    }
    func testCSVNeutralizesFormulaInjection() throws {
        var snapshot = LedgerSnapshot()
        snapshot.customers = [Customer(id: customerID, name: "=HYPERLINK(1)")]
        snapshot.transactions = [entry(500, .debt)]
        let csv = try ReportService.csv(snapshot: snapshot)
        XCTAssertTrue(csv.contains("'=HYPERLINK(1)")); XCTAssertTrue(csv.hasPrefix("\u{feff}"))
    }
}
