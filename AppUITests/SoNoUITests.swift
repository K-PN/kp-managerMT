import XCTest

final class SoNoUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["SONO_UI_TEST_STORE"] = UUID().uuidString
        app.launchArguments += ["-AppleLanguages", "(vi)", "-AppleLocale", "vi_VN"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Sổ Nợ AI"].waitForExistence(timeout: 30), "The real app must finish opening its ledger.")
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
        app.buttons["customer.save"].tap()
        let customer = app.staticTexts["Khach thu nghiem"].firstMatch
        XCTAssertTrue(customer.waitForExistence(timeout: 10))
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
            app.buttons["Thu nợ / thu khoản vay"].tap()
        }
        field.tap(); field.typeText(amount)
        let done = app.buttons["transaction.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        let confirmation = app.switches["transaction.confirmed"]
        for _ in 0..<3 where !confirmation.isHittable { app.swipeUp() }
        // SwiftUI exposes the whole labelled row as a switch; target its control end.
        confirmation.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        screenshot("draft-confirmation-\(amount)")
        XCTAssertEqual(confirmation.value as? String, "1")
        let save = app.buttons["transaction.save"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: save)
        waitForExpectations(timeout: 5)
        save.tap()
        XCTAssertTrue(app.buttons["customer.newTransaction"].waitForExistence(timeout: 10))
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
}
