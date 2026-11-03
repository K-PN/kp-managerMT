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
