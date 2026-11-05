import XCTest
@testable import SoNoAI
import SoNoCore
import PDFKit

final class AppSmokeTests: XCTestCase {
    func testCustomerStatementIncludesGoodsAndDebtAmount() throws {
        let customer = Customer(name: "Khánh", book: .debt)
        let entry = DebtTransaction(customerID: customer.id, amount: 20_000, kind: .debt, goodsDescription: "1 lon bò húc")
        let url = try PDFReports.statement(customer: customer, entries: [entry], balance: LedgerCalculator.balance([entry]), book: .debt)
        defer { try? FileManager.default.removeItem(at: url) }
        let text = try XCTUnwrap(PDFDocument(url: url)?.string)
        XCTAssertTrue(text.contains("1 lon bò húc")); XCTAssertTrue(text.contains("20.000"))
    }
    func testAccountStatementsOnlyIncludeRelevantTotals() throws {
        let customer = Customer(name: "An")
        let entries = [DebtTransaction(customerID: customer.id, amount: 20_000, kind: .debt)]
        let balance = try LedgerCalculator.balance(entries)
        let url = try PDFReports.statement(customer: customer, entries: entries, balance: balance, book: .debt)
        defer { try? FileManager.default.removeItem(at: url) }
        let text = try XCTUnwrap(PDFDocument(url: url)?.string)
        XCTAssertTrue(text.contains("20.000")); XCTAssertFalse(text.contains("tiền hàng"))
        let goods = [DebtTransaction(customerID: customer.id, amount: 30_000, kind: .purchase, goodsDescription: "Sữa")]
        let goodsURL = try PDFReports.statement(customer: customer, entries: goods, balance: LedgerCalculator.balance(goods), book: .goods)
        defer { try? FileManager.default.removeItem(at: goodsURL) }
        let goodsText = try XCTUnwrap(PDFDocument(url: goodsURL)?.string)
        XCTAssertTrue(goodsText.contains("30.000")); XCTAssertFalse(goodsText.contains("nợ khách")); XCTAssertFalse(goodsText.contains("Đã thu nợ"))
    }
    func testPDFContainsBrandAndGrandTotals() throws {
        let customer = Customer(name: "Nhà cung cấp An")
        var snapshot = LedgerSnapshot(); snapshot.customers = [customer]
        let proposal = try TransactionProposal(snapshot: snapshot, customerID: customer.id, kind: .purchase, amount: 1_000_000, paidNow: 400_000, goods: "10 thùng sữa")
        snapshot.transactions = proposal.entries
        let url = try PDFReports.trading(snapshot: snapshot, period: .month)
        defer { try? FileManager.default.removeItem(at: url) }
        let text = try XCTUnwrap(PDFDocument(url: url)?.string)
        XCTAssertTrue(text.contains("TẠP HÓA MỸ THẠNH")); XCTAssertTrue(text.contains("TỔNG CỘNG")); XCTAssertTrue(text.contains("600.000"))
    }
    @MainActor func testDisplayUsesVietnameseVND() {
        XCTAssertTrue(VND.string(500_000).contains("500"))
        XCTAssertTrue(VND.string(500_000).contains("₫"))
        XCTAssertNil(VND.string(500_000).range(of: #",\d{2}\s*₫"#, options: .regularExpression))
    }
    func testImagePreparationRejectsInvalidImage() async {
        do { _ = try await ImagePreparation.prepare(Data([1, 2, 3])); XCTFail("Invalid image accepted") } catch { }
    }
    func testUnsafeProxyConfigurationIsRejectedBeforeKeychainWrite() {
        // Unsigned Simulator apps cannot exercise device Keychain entitlements.
        // These invalid configurations must fail validation before any Keychain write.
        let validURL = URL(string: "https://example.invalid")!
        let expiration = Date().addingTimeInterval(600)
        let connections = [
            AIConnection(baseURL: URL(string: "http://example.invalid")!, token: "fixture", expiresAt: expiration),
            AIConnection(baseURL: URL(string: "https://user:password@example.invalid")!, token: "fixture", expiresAt: expiration),
            AIConnection(baseURL: validURL, token: "bad\r\nheader", expiresAt: expiration),
            AIConnection(baseURL: validURL, token: "fixture", expiresAt: Date().addingTimeInterval(-60)),
            AIConnection(baseURL: validURL, token: "fixture", expiresAt: Date().addingTimeInterval(7200))
        ]
        for connection in connections {
            XCTAssertThrowsError(try AIKeychain.save(connection)) { error in
                guard let ledgerError = error as? LedgerError, case .invalid = ledgerError else {
                    return XCTFail("Expected validation rejection before Keychain access, received \(error)")
                }
            }
        }
    }
}
