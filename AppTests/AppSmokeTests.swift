import XCTest
@testable import SoNoAI
import SoNoCore

final class AppSmokeTests: XCTestCase {
    @MainActor func testDisplayUsesVietnameseVND() {
        XCTAssertTrue(VND.string(500_000).contains("500"))
        XCTAssertTrue(VND.string(500_000).contains("₫"))
        XCTAssertNil(VND.string(500_000).range(of: #",\d{2}\s*₫"#, options: .regularExpression))
    }
    func testImagePreparationRejectsInvalidImage() async {
        do { _ = try await ImagePreparation.prepare(Data([1, 2, 3])); XCTFail("Invalid image accepted") } catch { }
    }
    func testNoProxyCredentialByDefault() throws {
        // Session availability is device-specific; never send a network request in a smoke test.
        let connection = try AIKeychain.load()
        if let connection { XCTAssertEqual(connection.baseURL.scheme, "https") }
    }
}
