import XCTest

final class SoNoUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["SONO_UI_TEST_STORE"] = UUID().uuidString
        app.launchEnvironment["SONO_UI_TEST_SPEECH"] = "1"
        app.launchArguments += ["-AppleLanguages", "(vi)", "-AppleLocale", "vi_VN"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Tạp Hóa Mỹ Thạnh"].waitForExistence(timeout: 30), "The real app must finish opening its ledger.")
    }
    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testMainScreensProduceRealScreenshots() {
        screenshot("01-dashboard")
        for (tab, title, name) in [("Khách hàng", "Khách hàng", "02-customers"), ("Sổ giao dịch", "Sổ giao dịch", "03-ledger"), ("Cài đặt", "Cài đặt", "04-settings")] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10))
            screenshot(name)
        }
    }
    func testCreateCustomerDebtAndPartialCollection() {
        app.tabBars.buttons["Khách hàng"].tap()
        app.buttons["customer.add"].tap()
        let name = app.textFields["customer.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap(); name.typeText("Khach thu nghiem")
        XCTAssertEqual(name.value as? String, "Khach thu nghiem", app.debugDescription)
        let save = app.buttons["customer.save"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: save)
        waitForExpectations(timeout: 10)
        save.tap()
        let customer = app.staticTexts["Khach thu nghiem"].firstMatch
        XCTAssertTrue(customer.waitForExistence(timeout: 15), app.debugDescription)
        customer.tap()
        post(amount: "500000", collection: false)
        assertReceivable(contains: "500.000")
        screenshot("05-customer-after-debt")
        post(amount: "200000", collection: true)
        assertReceivable(contains: "300.000")
        screenshot("06-customer-after-partial-payment")
    }
    private func post(amount: String, collection: Bool) {
        app.buttons["customer.newTransaction"].tap()
        let field = app.textFields["transaction.amount"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        if collection {
            app.buttons["transaction.kind"].tap()
            app.buttons["Thu nợ"].tap()
        }
        field.tap(); field.typeText(amount)
        let done = app.buttons["transaction.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        confirmTransaction(screenshotName: "draft-confirmation-\(amount)")
        let save = app.buttons["transaction.save"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: save)
        waitForExpectations(timeout: 5)
        save.tap()
        XCTAssertTrue(app.buttons["customer.newTransaction"].waitForExistence(timeout: 10))
    }
    private func confirmTransaction(screenshotName: String) {
        let confirmation = app.switches["transaction.confirmed"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10))
        // A partly visible SwiftUI row can be hittable while its switch thumb
        // remains below the form viewport. Bring the entire row into view.
        let viewport = app.windows.firstMatch.frame.insetBy(dx: 0, dy: 100)
        for _ in 0..<5 {
            if confirmation.isHittable && viewport.contains(confirmation.frame) { break }
            app.swipeUp()
        }
        screenshot("before-\(screenshotName)")
        XCTAssertTrue(confirmation.isHittable && viewport.contains(confirmation.frame), app.debugDescription)
        XCTAssertEqual(confirmation.value as? String, "0", "Confirmation must start off")
        // SwiftUI exposes the labelled row as a switch; tap its control end.
        confirmation.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        expectation(for: NSPredicate(format: "value == %@", "1"), evaluatedWith: confirmation)
        waitForExpectations(timeout: 5)
        screenshot(screenshotName)
    }
    private func assertReceivable(contains amount: String) {
        let balance = app.descendants(matching: .any).matching(identifier: "customer.receivable").firstMatch
        XCTAssertTrue(balance.waitForExistence(timeout: 10))
        let predicate = NSPredicate { _, _ in
            (balance.label + " " + (balance.value as? String ?? "")).contains(amount)
        }
        expectation(for: predicate, evaluatedWith: nil)
        waitForExpectations(timeout: 10)
    }
    private func addCustomer(_ value: String) {
        app.tabBars.buttons["Khách hàng"].tap()
        app.buttons["customer.add"].tap()
        let field = app.textFields["customer.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText(value)
        XCTAssertEqual(field.value as? String, value)
        app.buttons["customer.save"].tap()
        let customer = app.staticTexts[value].firstMatch
        XCTAssertTrue(customer.waitForExistence(timeout: 15), app.debugDescription); customer.tap()
    }
    func testGoodsPartialPaymentDashboardFiltersAndReportTotals() {
        addCustomer("Nha cung cap An")
        app.buttons["customer.newTransaction"].tap()
        app.buttons["transaction.kind"].tap(); app.buttons["Nhập hàng"].tap()
        let goods = app.descendants(matching: .any).matching(identifier: "transaction.goods").firstMatch
        XCTAssertTrue(goods.waitForExistence(timeout: 10)); goods.tap(); goods.typeText("10 thung sua")
        let total = app.textFields["transaction.amount"]; total.tap(); total.typeText("1000000")
        app.buttons["transaction.done"].tap()
        let paid = app.textFields["transaction.paid"]; paid.tap(); paid.typeText(XCUIKeyboardKey.delete.rawValue + "400000")
        XCTAssertEqual(paid.value as? String, "400000"); app.buttons["transaction.done"].tap()
        confirmTransaction(screenshotName: "11-goods-before-confirm")
        app.buttons["transaction.save"].tap()
        XCTAssertTrue(app.buttons["customer.newTransaction"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "customer.goodsPayable").firstMatch.waitForExistence(timeout: 10))
        app.tabBars.buttons["Tổng quan"].tap()
        let month = app.buttons["dashboard.goodsMonth"]
        XCTAssertTrue(month.waitForExistence(timeout: 10))
        screenshot("12-dashboard-goods")
        month.tap()
        XCTAssertTrue(app.switches["ledger.dateFilter"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.switches["ledger.dateFilter"].value as? String, "1")
        screenshot("13-ledger-date-range")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Báo cáo"].tap()
        XCTAssertTrue(app.staticTexts["Tổng tiền hàng"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "600.000")).firstMatch.exists)
        screenshot("14-report-totals")
    }
    func testVoiceNewCustomerRemainsTemporaryUntilConfirmation() {
        app.buttons["voice.open"].tap()
        let field = app.textViews["voice.transcript"]
        XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText("Thêm khách mới Chi Mai ghi nợ 300 nghìn")
        app.buttons["voice.done"].tap()
        app.buttons["voice.analyze"].tap()
        XCTAssertTrue(app.textFields["voice.newName"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["voice.newName"].value as? String, "Chi Mai")
        screenshot("15-voice-temporary")
        app.buttons["Đóng"].tap()
        app.tabBars.buttons["Khách hàng"].tap()
        XCTAssertFalse(app.staticTexts["Chi Mai"].exists, "A preview must not create a customer")
        app.buttons["voice.open"].tap()
        let again = app.textViews["voice.transcript"]
        XCTAssertTrue(again.waitForExistence(timeout: 10)); again.tap(); again.typeText("Thêm khách mới Chi Mai ghi nợ 300 nghìn")
        app.buttons["voice.done"].tap()
        app.buttons["voice.analyze"].tap()
        let confirm = app.buttons["voice.confirm"]
        for _ in 0..<4 where !confirm.isHittable { app.swipeUp() }
        XCTAssertTrue(confirm.isEnabled); confirm.tap()
        XCTAssertTrue(app.otherElements["voice.saved"].waitForExistence(timeout: 10) || app.staticTexts["Đã xác nhận và lưu"].exists)
        app.buttons["Đóng"].tap()
        let customer = app.staticTexts["Chi Mai"].firstMatch
        XCTAssertTrue(customer.waitForExistence(timeout: 10)); customer.tap()
        assertReceivable(contains: "300.000")
        screenshot("16-voice-created-customer")
    }
}
