import XCTest
@testable import SoNoCore

final class TradingTests: XCTestCase {
    private func ledger() throws -> LedgerService {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try LedgerService(databaseURL: folder.appendingPathComponent("test.sqlite"))
    }
    func testPurchaseAndPartialPaymentAreOneConfirmationAndPreserveOldDebt() async throws {
        let service = try ledger(), customer = Customer(name: "Nhà cung cấp An")
        try await service.saveCustomer(customer)
        try await service.post([DebtTransaction(customerID: customer.id, amount: 500_000, kind: .debt)], confirmed: true)
        let before = try await service.snapshot()
        let preview = try TransactionProposal(snapshot: before, customerID: customer.id, kind: .purchase, amount: 1_000_000, paidNow: 400_000, goods: "10 thùng sữa")
        XCTAssertEqual(preview.before.receivable, 500_000)
        XCTAssertEqual(preview.after.receivable, 500_000)
        XCTAssertEqual(preview.after.goodsPayable, 600_000)
        let unchanged = try await service.snapshot(); XCTAssertEqual(unchanged, before)
        do { try await service.confirm(preview, confirmed: false); XCTFail("Unconfirmed preview was written") } catch { }
        let stillUnchanged = try await service.snapshot(); XCTAssertEqual(stillUnchanged, before)
        try await service.confirm(preview, confirmed: true)
        let balance = try await service.balance(customerID: customer.id)
        XCTAssertEqual(balance.goodsPayable, 600_000); XCTAssertEqual(balance.receivable, 500_000)
        let reopened = try await service.snapshot()
        XCTAssertEqual(reopened.transactions.filter { $0.kind == .purchase }.first?.goodsDescription, "10 thùng sữa")
        XCTAssertThrowsError(try TransactionProposal(snapshot: reopened, customerID: customer.id, kind: .supplierPayment, amount: 600_001))
    }
    func testNewCustomerAndEntriesRollbackTogetherOnDuplicate() async throws {
        let service = try ledger(), customer = Customer(name: "Chị Mai")
        let preview = try TransactionProposal(snapshot: LedgerSnapshot(), customerID: customer.id, kind: .debt, amount: 300_000, source: .voice, newCustomer: customer)
        let empty = try await service.snapshot(); XCTAssertTrue(empty.customers.isEmpty)
        try await service.confirm(preview, confirmed: true)
        let saved = try await service.snapshot(); XCTAssertEqual(saved.customers.count, 1); XCTAssertEqual(saved.transactions.count, 1)
        let duplicate = Customer(name: "Chi Mai")
        let other = try TransactionProposal(snapshot: saved, customerID: duplicate.id, kind: .debt, amount: 1, newCustomer: duplicate)
        do { try await service.confirm(other, confirmed: true); XCTFail("Duplicate accepted") } catch { }
        let unchanged = try await service.snapshot(); XCTAssertEqual(unchanged, saved)
    }
    func testRepeatedConfirmationCannotDuplicateCustomerOrPayments() async throws {
        let service = try ledger(), customer = Customer(name: "Nhà cung cấp mới")
        let proposal = try TransactionProposal(snapshot: LedgerSnapshot(), customerID: customer.id, kind: .purchase, amount: 1_000, paidNow: 400, goods: "Gạo", newCustomer: customer)
        // Race with another confirmation: the same immutable entry UUID cannot be written twice.
        try await service.confirm(proposal, confirmed: true)
        let before = try await service.snapshot()
        do { try await service.confirm(proposal, confirmed: true); XCTFail("Repeated confirmation accepted") } catch { }
        let after = try await service.snapshot(); XCTAssertEqual(after, before)
    }
    func testOldTransactionJSONWithoutGoodsFieldsStillDecodes() throws {
        let entry = DebtTransaction(customerID: UUID(), amount: 10, kind: .borrowing)
        var object = try JSONSerialization.jsonObject(with: JSONCoding.encode(entry)) as! [String: Any]
        object.removeValue(forKey: "goodsDescription"); object.removeValue(forKey: "relatedPurchaseID")
        let decoded = try JSONDecoder().decode(DebtTransaction.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.kind, .borrowing); XCTAssertNil(decoded.goodsDescription)
        XCTAssertEqual(try LedgerCalculator.balance([decoded]).payable, 10)
    }
    func testDashboardPeriodsReversalsAndCSVGrandTotals() throws {
        let calendar = VietnameseDate.calendar
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12))!
        let customer = Customer(name: "An")
        var state = LedgerSnapshot(); state.customers = [customer]
        func purchase(_ amount: Int64, _ day: Int) -> DebtTransaction {
            DebtTransaction(customerID: customer.id, amount: amount, kind: .purchase, effectiveDate: calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: 9))!, goodsDescription: "Gạo")
        }
        let reversed = purchase(700, 2)
        state.transactions = [purchase(1_000, 1), purchase(2_000, 3), reversed,
            DebtTransaction(customerID: customer.id, amount: 700, kind: .reversal, reversalOf: reversed.id),
            DebtTransaction(customerID: customer.id, amount: 500, kind: .supplierPayment, effectiveDate: now)]
        let summary = try DashboardSummary(snapshot: state, now: now)
        XCTAssertEqual(summary.goodsThisMonth, 3_000); XCTAssertEqual(summary.goodsThisWeek, 2_000)
        XCTAssertEqual(summary.goodsPayable, 2_500)
        let totals = try ReportService.totals(snapshot: state)
        XCTAssertEqual(totals.purchases, 3_000); XCTAssertEqual(totals.paid, 500); XCTAssertEqual(totals.goodsPayable, 2_500)
        let csv = try ReportService.csv(snapshot: state)
        XCTAssertTrue(csv.contains("TỔNG TIỀN HÀNG\",\"3000")); XCTAssertTrue(csv.contains("TỔNG NỢ TIỀN HÀNG\",\"2500"))
    }
    func testDateRangeIncludesWholeLastDayAndRejectsReversedRange() {
        let calendar = VietnameseDate.calendar
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4))!
        XCTAssertTrue(LedgerDateRange.contains(end.addingTimeInterval(86_399), from: start, through: end))
        XCTAssertFalse(LedgerDateRange.contains(end.addingTimeInterval(86_400), from: start, through: end))
        XCTAssertFalse(LedgerDateRange.contains(start, from: end, through: start))
    }
    func testVoiceNewCustomerAndPurchaseWithExplicitPaidAmount() {
        let parser = VietnameseVoiceParser(), an = Customer(name: "Anh An")
        let purchase = parser.parse("Nhập hàng của Anh An gồm 10 thùng sữa tổng 2 triệu đã trả 500 nghìn", customers: [an], now: Date())
        XCTAssertEqual(purchase.intent, .purchase); XCTAssertEqual(purchase.amount, 2_000_000)
        XCTAssertEqual(purchase.paidNow, 500_000); XCTAssertEqual(purchase.goodsDescription, "10 thùng sữa")
        let create = parser.parse("Thêm khách mới Chị Mai ghi nợ 300 nghìn", customers: [], now: Date())
        XCTAssertEqual(create.intent, .debt); XCTAssertEqual(create.newCustomerName, "Chị Mai"); XCTAssertEqual(create.amount, 300_000)
        let name = parser.parse("Chị Trang ghi nợ 500 nghìn", customers: [Customer(name: "Chị Trang")], now: Date())
        XCTAssertEqual(name.intent, .debt)
    }
}
