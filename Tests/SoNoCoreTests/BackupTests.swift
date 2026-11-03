#if canImport(CryptoKit) && canImport(CommonCrypto)
import XCTest
@testable import SoNoCore

final class BackupTests: XCTestCase {
    func testEncryptedRoundTripWithAttachmentsAndDrafts() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ledger = try LedgerService(databaseURL: folder.appendingPathComponent("test.sqlite"))
        let customer = Customer(name: "Nam"), image = Attachment(data: Data([4, 5, 6]))
        try await ledger.saveCustomer(customer)
        try await ledger.post([DebtTransaction(customerID: customer.id, amount: 500, kind: .debt, attachmentIDs: [image.id])], attachments: [image], confirmed: true)
        try await ledger.saveDraft(SavedDraft(id: UUID(), data: Data("nháp".utf8)))
        let service = LocalBackupService(ledger: ledger), before = try await ledger.snapshot()
        let data = try await service.export(password: "mat-khau-rat-dai")
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(envelope["encrypted"] as? Bool, true)
        let payload = try XCTUnwrap((envelope["payload"] as? String).flatMap { Data(base64Encoded: $0) })
        XCTAssertNotEqual(payload, try JSONCoding.encode(before))
        do { try await service.restore(data, password: "sai", confirmed: true); XCTFail("Wrong password must fail") } catch { }
        let afterWrong = try await ledger.snapshot(); XCTAssertEqual(before, afterWrong)
        try await service.restore(data, password: "mat-khau-rat-dai", confirmed: true)
        let restored = try await ledger.snapshot()
        XCTAssertEqual(restored.customers, before.customers); XCTAssertEqual(restored.transactions, before.transactions)
        XCTAssertEqual(restored.attachments, [image]); XCTAssertEqual(restored.drafts, before.drafts)
    }
    func testPlainBackupTamperFailsAndWeakPasswordRejected() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ledger = try LedgerService(databaseURL: folder.appendingPathComponent("test.sqlite")), service = LocalBackupService(ledger: ledger)
        let plain = try await service.export(password: nil)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: plain) as? [String: Any])
        object["digest"] = Data([0]).base64EncodedString()
        let tampered = try JSONSerialization.data(withJSONObject: object)
        do { try await service.restore(tampered, password: nil, confirmed: true); XCTFail("Tamper must fail") } catch { }
        do { _ = try await service.export(password: "short"); XCTFail("Weak password must fail") } catch { }
    }
}
#endif
