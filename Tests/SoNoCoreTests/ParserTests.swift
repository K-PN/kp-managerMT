import XCTest
@testable import SoNoCore

final class ParserTests: XCTestCase {
    func testVietnameseMoneyPhrases() {
        let cases: [(String, Int64)] = [("500 nghìn", 500_000), ("500 ngàn", 500_000), ("Năm trăm k", 500_000), ("Một triệu rưỡi", 1_500_000), ("Một triệu hai trăm", 1_200_000), ("Hai triệu ba trăm năm mươi nghìn", 2_350_000), ("Một triệu không trăm năm mươi nghìn", 1_050_000), ("2,5 triệu", 2_500_000), ("500.000", 500_000), ("250000", 250_000), ("500k", 500_000), ("500.000 ₫", 500_000), ("500.000 đ", 500_000)]
        for (text, expected) in cases { XCTAssertEqual(VietnameseMoneyParser().parse(text).amount, expected, text) }
    }
    func testAmbiguousOrInvalidMoneyIsNeverAccepted() {
        for text in ["Hai triệu ba", "-500", "0", "một ít", "1,5", "1 triệu triệu", "9223372036854775808"] {
            XCTAssertNil(VietnameseMoneyParser().parse(text).amount, text)
        }
        XCTAssertEqual(VietnameseMoneyParser().parse("hai triệu ba").alternatives, [2_000_003, 2_300_000])
    }
    func testVoiceCommandDebtAndPayment() {
        let nam = Customer(name: "Nguyễn Văn Nam"), lan = Customer(name: "Trần Thị Lan")
        let parser = VietnameseVoiceParser(), now = Date()
        let debt = parser.parse("Anh Nam lấy thêm hàng 350 nghìn.", customers: [nam, lan], now: now)
        XCTAssertEqual(debt.intent, .debt); XCTAssertEqual(debt.amount, 350_000); XCTAssertEqual(debt.candidateIDs, [nam.id])
        let payment = parser.parse("Chị Lan vừa trả 2 triệu rưỡi.", customers: [nam, lan], now: now)
        XCTAssertEqual(payment.intent, .collection); XCTAssertEqual(payment.amount, 2_500_000)
    }
    func testQuantityAndYesterdayUseDeterministicMath() {
        let customer = Customer(name: "Anh Hùng"), now = Date()
        let draft = VietnameseVoiceParser().parse("Hôm qua anh Hùng mua 5 bao xi măng mỗi bao 90 nghìn, ghi nợ.", customers: [customer], now: now)
        XCTAssertEqual(draft.amount, 450_000)
        XCTAssertTrue(VietnameseDate.calendar.isDate(draft.effectiveDate, inSameDayAs: VietnameseDate.calendar.date(byAdding: .day, value: -1, to: now)!))
    }
    func testDuplicateNameRequiresSelectionAndAccentInsensitiveNicknameMatches() {
        let a = Customer(name: "Nguyễn Văn Nam", nickname: "Bảy"), b = Customer(name: "Trần Văn Nam")
        let draft = VietnameseVoiceParser().parse("Anh Nam lấy thêm hàng 500 nghìn", customers: [a, b], now: Date())
        XCTAssertEqual(Set(draft.candidateIDs), Set([a.id, b.id])); XCTAssertFalse(draft.warnings.isEmpty)
        XCTAssertEqual(CustomerMatcher.match("Bay mua hàng", customers: [a, b]).map(\.id), [a.id])
        XCTAssertTrue(a.matches("nguyen")); XCTAssertTrue(Customer(name: "Đức").matches("duc"))
    }
    func testQueriesAndUnknownIntent() {
        let parser = VietnameseVoiceParser()
        XCTAssertEqual(parser.parse("Anh Minh còn nợ bao nhiêu?", customers: [], now: Date()).intent, .balance)
        XCTAssertEqual(parser.parse("Hôm nay ai trả tiền cho tôi?", customers: [], now: Date()).intent, .todayCollections)
        XCTAssertEqual(parser.parse("Cho tôi xem các khoản nợ quá hạn", customers: [], now: Date()).intent, .overdue)
        XCTAssertEqual(parser.parse("xin chào", customers: [], now: Date()).intent, .unknown)
    }
    func testNotebookExampleAndReviewGate() throws {
        let nam = Customer(name: "Anh Nam"), attachmentID = UUID()
        let text = "Anh Nam\n12/10/2020: 500.000\n14/10/2020: 250.000\n16/10/2020: Trả 300.000"
        var rows = NotebookParser().parse(text, attachmentID: attachmentID, customers: [nam])
        XCTAssertEqual(rows.count, 3); XCTAssertThrowsError(try rows[0].transaction())
        for i in rows.indices { rows[i].confirmed = true }
        XCTAssertEqual(try LedgerCalculator.balance(rows.map { try $0.transaction() }).receivable, 450_000)
        XCTAssertTrue(rows.allSatisfy { $0.attachmentID == attachmentID })
    }
    func testNotebookMissingYearInvalidDateAndQuantityMismatch() {
        let rows = NotebookParser().parse("Anh Nam\n31/02: 500.000", attachmentID: UUID(), customers: [])
        XCTAssertNotNil(rows.first?.warning); XCTAssertFalse(rows.first?.confirmed ?? true)
        let row = OCRRow(attachmentID: UUID(), rawText: "", customerID: UUID(), amount: 500, date: Date(), confirmed: true, quantity: 2, unitPrice: 200)
        XCTAssertThrowsError(try row.transaction())
    }
    func testAmbiguousVoiceCannotSupplyAnAmount() {
        let draft = VietnameseVoiceParser().parse("Anh Nam lấy thêm hàng hai triệu ba", customers: [Customer(name: "Anh Nam")], now: Date())
        XCTAssertNil(draft.amount); XCTAssertFalse(draft.warnings.isEmpty)
    }
}
