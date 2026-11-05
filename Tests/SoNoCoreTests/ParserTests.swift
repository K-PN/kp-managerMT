import XCTest
@testable import SoNoCore

final class ParserTests: XCTestCase {
    func testAppleSpeechFormattedVNDNeedsNoCurrencySuffix() {
        let parser = VietnameseVoiceParser()
        for text in ["nợ 50.000", "Nợ 50000", "Ghi nợ 50.000.", "Chị Mai nợ 50.000", "Thu nợ 50.000", "Trả xe An 50.000"] {
            XCTAssertEqual(parser.parse(text, customers: []).amount, 50_000, text)
        }
        XCTAssertTrue(VietnameseMoneyParser().spans(in: "nợ 50.000").isEmpty, "OCR must keep its explicit-unit rule")
        XCTAssertEqual(parser.parse("Thu nợ 50.000", customers: []).intent, .collection)
    }
    func testFormattedPurchaseTotalAndPaidIgnoreItemQuantity() {
        let draft = VietnameseVoiceParser().parse("Xe An nợ tiền hàng gồm 2 thùng sữa tổng 50.000 đã trả 20.000 còn nợ 30.000", customers: [])
        XCTAssertEqual(draft.intent, .purchase); XCTAssertEqual(draft.amount, 50_000)
        XCTAssertEqual(draft.paidNow, 20_000); XCTAssertEqual(draft.newCustomerName, "Xe An")
        let short = VietnameseVoiceParser().parse("Xe An nợ 50.000 đã trả 20.000", customers: [])
        XCTAssertEqual(short.intent, .purchase); XCTAssertEqual(short.amount, 50_000); XCTAssertEqual(short.paidNow, 20_000)
        XCTAssertEqual(VietnameseVoiceParser().parse("Xe An nợ tiền hàng 50.000", customers: []).amount, 50_000)
        for text in ["Trả tiền hàng xe An 50.000", "Trả nợ tiền hàng xe An 50.000"] {
            let payment = VietnameseVoiceParser().parse(text, customers: [])
            XCTAssertEqual(payment.intent, .supplierPayment, text); XCTAssertEqual(payment.amount, 50_000, text)
        }
    }
    func testBareAmountsDoNotTurnQuantitiesDatesOrPhonesIntoMoney() {
        for text in ["Nợ 5 bao gạo", "Xe An mua 2 thùng sữa", "Nợ ngày 05/11/2026", "Xe An số điện thoại 0901234567", "Nợ -50000", "Nợ 50.000 và 20.000", "Nợ 50.000, nợ 20.000"] {
            XCTAssertNil(VietnameseVoiceParser().parse(text, customers: []).amount, text)
        }
    }
    func testSupplierNamesAreCapturedWithoutExplicitAddCommand() {
        for name in ["xe Hùng", "nhà xe Mỹ Thạnh", "nhà cung cấp An Phát", "công ty ABC Việt Nam"] {
            let draft = VietnameseVoiceParser().parse("Nợ \(name) 50.000", customers: [])
            XCTAssertEqual(draft.intent, .purchase); XCTAssertEqual(draft.amount, 50_000)
            XCTAssertEqual(draft.newCustomerName, name)
        }
    }
    func testSupplierPrefixMatchesExistingWholeNameAndNeverLastWordAlone() {
        let supplier = Customer(name: "An Phát", book: .goods)
        let other = Customer(name: "Bình Phát", book: .goods)
        let draft = VietnameseVoiceParser().parse("Nhà cung cấp An Phát nợ 50.000", customers: [supplier, other])
        XCTAssertEqual(draft.candidateIDs, [supplier.id]); XCTAssertNil(draft.newCustomerName)
        let unknown = VietnameseVoiceParser().parse("Xe Tân Phát nợ 50.000", customers: [supplier, other])
        XCTAssertTrue(unknown.candidateIDs.isEmpty); XCTAssertEqual(unknown.newCustomerName, "Xe Tân Phát")
        let query = VietnameseVoiceParser().parse("Tra cứu nợ công ty An Phát", customers: [supplier])
        XCTAssertEqual(query.candidateIDs, [supplier.id]); XCTAssertNil(query.newCustomerName)
    }
    func testExactSupplierPrefixWinsAndDuplicateNamesRemainAmbiguous() {
        let truck = Customer(name: "Xe An", book: .goods), company = Customer(name: "Công ty An", book: .goods)
        XCTAssertEqual(VietnameseVoiceParser().parse("Xe An nợ 50.000", customers: [truck, company]).candidateIDs, [truck.id])
        let a = Customer(name: "An Phát", book: .goods), b = Customer(name: "An Phát", book: .goods)
        let draft = VietnameseVoiceParser().parse("Nhà cung cấp An Phát nợ 50.000", customers: [a, b])
        XCTAssertEqual(Set(draft.candidateIDs), Set([a.id, b.id])); XCTAssertNil(draft.newCustomerName)
    }
    func testDebtWithoutSpokenDongAndAtStartOfSentence() {
        for text in ["Nợ 20 nghìn", "Nợ hai mươi nghìn", "Ghi nợ 20 ngàn", "Chị Mai nợ 20 nghìn."] {
            let draft = VietnameseVoiceParser().parse(text, customers: [Customer(name: "Chị Mai")])
            XCTAssertEqual(draft.intent, .debt, text)
            XCTAssertEqual(draft.amount, 20_000, text)
        }
    }
    func testSupplierCuesRouteDebtPaymentAndLookup() {
        for name in ["Xe An", "Nhà cung cấp An", "Công ty An"] {
            let supplier = Customer(name: name, book: .goods)
            let parser = VietnameseVoiceParser()
            let debt = parser.parse("\(name) nợ 20 nghìn", customers: [supplier])
            XCTAssertEqual(debt.intent, .purchase); XCTAssertEqual(debt.amount, 20_000)
            XCTAssertEqual(debt.paidNow, 0); XCTAssertEqual(debt.candidateIDs, [supplier.id])
            XCTAssertNotNil(debt.goodsDescription)
            XCTAssertEqual(parser.parse("Trả \(name) 10 nghìn", customers: [supplier]).intent, .supplierPayment)
            let query = parser.parse("Tra cứu nợ \(name)", customers: [supplier])
            XCTAssertEqual(query.intent, .supplierBalance); XCTAssertTrue(query.isQuery)
        }
        XCTAssertEqual(VietnameseVoiceParser().parse("Tra cứu khách An", customers: []).intent, .balance)
    }
    func testSameNameDoesNotCrossCustomerAndSupplierBooks() {
        let customer = Customer(name: "An", book: .debt), supplier = Customer(name: "An", book: .goods)
        let parser = VietnameseVoiceParser()
        XCTAssertEqual(parser.parse("An nợ 20 nghìn", customers: [customer, supplier]).candidateIDs, [customer.id])
        XCTAssertEqual(parser.parse("Xe An nợ 20 nghìn", customers: [customer, supplier]).candidateIDs, [supplier.id])
        XCTAssertFalse(AccountBook.hasSupplierCue("Anh Xem nợ 20 nghìn"))
    }
    func testNewSupplierVoiceKeepsNameAndVND() {
        let draft = VietnameseVoiceParser().parse("Thêm xe An nợ 20 nghìn", customers: [])
        XCTAssertEqual(draft.intent, .purchase); XCTAssertEqual(draft.newCustomerName, "xe An")
        XCTAssertEqual(draft.amount, 20_000)
    }
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
    func testNewCustomerKeywordDoesNotEraseDebtAmount() {
        for text in ["Thêm khách mới Chị Mai ghi nợ 300 nghìn", "Tạo khách mới Chị Mai ghi nợ ba trăm nghìn", "Them khach moi Chi Mai ghi no 300 nghin"] {
            let draft = VietnameseVoiceParser().parse(text, customers: [])
            XCTAssertEqual(draft.intent, .debt, text)
            XCTAssertEqual(draft.amount, 300_000, text)
            XCTAssertNotNil(draft.newCustomerName, text)
            XCTAssertFalse(draft.warnings.contains { $0.contains("đơn giá") }, text)
        }
    }
    func testUnitPricingStillAppliesWhenAddingNewCustomer() {
        let parser = VietnameseVoiceParser()
        let draft = parser.parse("Thêm khách mới Chị Mai mua 5 bao gạo mỗi bao 90 nghìn", customers: [])
        XCTAssertEqual(draft.newCustomerName, "Chị Mai")
        XCTAssertEqual(draft.amount, 450_000)
        let incomplete = parser.parse("Thêm khách mới Chị Mai mua gạo mỗi bao 90 nghìn", customers: [])
        XCTAssertNil(incomplete.amount)
        XCTAssertTrue(incomplete.warnings.contains { $0.contains("đơn giá") })
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
