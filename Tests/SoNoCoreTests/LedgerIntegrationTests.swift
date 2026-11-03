import XCTest
@testable import SoNoCore

final class LedgerIntegrationTests: XCTestCase {
    private func makeLedger() throws -> (LedgerService, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (try LedgerService(databaseURL: folder.appendingPathComponent("test.sqlite")), folder)
    }
    private func expectError(_ operation: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("Expected error", file: file, line: line) } catch { }
    }
    func testCreateUpdateAndDuplicateNames() async throws {
        let (ledger, _) = try makeLedger()
        var customer = Customer(name: "Nguyễn Văn Nam")
        try await ledger.saveCustomer(customer)
        await expectError { try await ledger.saveCustomer(Customer(name: "Nguyen Van Nam")) }
        try await ledger.saveCustomer(Customer(name: "Nguyen Van Nam"), allowDuplicate: true)
        customer.phone = "0900000000"; try await ledger.saveCustomer(customer)
        let snapshot = try await ledger.snapshot()
        XCTAssertEqual(snapshot.customers.count, 2); XCTAssertEqual(snapshot.audit.count, 3)
    }
    func testFinancialWriteAndAuditRollbackTogether() async throws {
        let (ledger, _) = try makeLedger(), customer = Customer(name: "Nam")
        try await ledger.saveCustomer(customer)
        let debt = DebtTransaction(customerID: customer.id, amount: 500, kind: .debt, effectiveDate: Date(timeIntervalSince1970: 10))
        try await ledger.post([debt], confirmed: true)
        let before = try await ledger.snapshot()
        await expectError { try await ledger.post([DebtTransaction(customerID: customer.id, amount: 501, kind: .collection)], confirmed: true) }
        let after = try await ledger.snapshot()
        XCTAssertEqual(before, after)
        XCTAssertTrue(after.audit.contains { $0.entityID == debt.id })
    }
    func testOCRBatchIsAtomicAndDuplicateProtected() async throws {
        let (ledger, _) = try makeLedger(), customer = Customer(name: "Nam"), image = Attachment(data: Data([1, 2, 3]))
        try await ledger.saveCustomer(customer)
        let debt = DebtTransaction(customerID: customer.id, amount: 500, kind: .debt, effectiveDate: Date(timeIntervalSince1970: 10), source: .ocr, attachmentIDs: [image.id], importKey: "row-1")
        let bad = DebtTransaction(customerID: customer.id, amount: 600, kind: .collection, source: .ocr)
        await expectError { try await ledger.post([debt, bad], attachments: [image], confirmed: true) }
        let empty = try await ledger.snapshot(); XCTAssertTrue(empty.transactions.isEmpty); XCTAssertTrue(empty.attachments.isEmpty)
        try await ledger.post([debt], attachments: [image], confirmed: true)
        await expectError { try await ledger.post([debt], confirmed: true) }
        let duplicate = DebtTransaction(customerID: customer.id, amount: 500, kind: .debt, effectiveDate: debt.effectiveDate, source: .ocr)
        await expectError { try await ledger.post([duplicate], confirmed: true) }
    }
    func testReversalCorrectionAndRebuild() async throws {
        let (ledger, _) = try makeLedger(), customer = Customer(name: "Nam")
        try await ledger.saveCustomer(customer)
        let debt = DebtTransaction(customerID: customer.id, amount: 500, kind: .debt, effectiveDate: Date(timeIntervalSince1970: 10))
        try await ledger.post([debt], confirmed: true)
        let replacement = DebtTransaction(customerID: customer.id, amount: 600, kind: .debt, effectiveDate: debt.effectiveDate)
        try await ledger.correct(debt.id, replacement: replacement, reason: "Nhập thiếu")
        let snapshot = try await ledger.snapshot(), balance = try await ledger.balance(customerID: customer.id)
        XCTAssertEqual(snapshot.transactions.count, 3); XCTAssertEqual(balance.receivable, 600)
        XCTAssertEqual(try LedgerCalculator.balance(snapshot.transactions), balance)
        await expectError { try await ledger.reverse(debt.id, reason: "Lặp") }
    }
    func testConfirmedMergePreservesOriginalTransactionCustomerIDs() async throws {
        let (ledger, _) = try makeLedger(), a = Customer(name: "Nam"), b = Customer(name: "Nam 2")
        try await ledger.saveCustomer(a); try await ledger.saveCustomer(b)
        let entry = DebtTransaction(customerID: a.id, amount: 500, kind: .debt)
        try await ledger.post([entry], confirmed: true)
        await expectError { try await ledger.mergeCustomer(a.id, into: b.id, confirmed: false) }
        try await ledger.mergeCustomer(a.id, into: b.id, confirmed: true)
        let state = try await ledger.snapshot(), balance = try await ledger.balance(customerID: b.id)
        XCTAssertEqual(balance.receivable, 500); XCTAssertEqual(state.transactions.first?.customerID, a.id)
        XCTAssertEqual(try state.rootID(a.id), b.id)
    }
    func testOfflinePersistenceSurvivesReopeningAndDraftIsSaved() async throws {
        let (ledger, folder) = try makeLedger(), customer = Customer(name: "Ngoại tuyến")
        try await ledger.saveCustomer(customer)
        let draft = SavedDraft(id: UUID(), data: Data("bản nháp".utf8)); try await ledger.saveDraft(draft)
        let reopened = try LedgerService(databaseURL: folder.appendingPathComponent("test.sqlite"))
        let state = try await reopened.snapshot()
        XCTAssertEqual(state.customers.map(\.id), [customer.id]); XCTAssertEqual(state.customers.first?.name, customer.name)
        XCTAssertEqual(state.drafts, [draft])
    }
    func testRestoreValidationFailureLeavesDatabaseUnchanged() async throws {
        let (ledger, _) = try makeLedger(), customer = Customer(name: "Nam")
        try await ledger.saveCustomer(customer)
        let before = try await ledger.snapshot()
        var corrupt = before; corrupt.schemaVersion = 999
        await expectError { try await ledger.restoreSnapshot(corrupt, confirmed: true) }
        let after = try await ledger.snapshot(); XCTAssertEqual(before, after)
    }
    func testRestoreRetainsPriorAuditAndAddsRestoreEvent() async throws {
        let (ledger, _) = try makeLedger(), a = Customer(name: "A"), b = Customer(name: "B")
        try await ledger.saveCustomer(a); let backup = try await ledger.snapshot()
        try await ledger.saveCustomer(b)
        try await ledger.restoreSnapshot(backup, confirmed: true)
        let restored = try await ledger.snapshot()
        XCTAssertEqual(restored.customers.map(\.id), [a.id]); XCTAssertEqual(restored.audit.count, 3)
        XCTAssertTrue(restored.audit.contains { $0.event == "Khôi phục sao lưu" })
    }
    func testMigrationAndNewerSchemaRejection() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("test.sqlite"), store = try SQLiteStore(url: url)
        XCTAssertEqual(try store.scalar("PRAGMA user_version"), "1")
        try store.execute("PRAGMA user_version = 99")
        XCTAssertThrowsError(try SQLiteStore(url: url))
    }
    func testAuditIsAppendOnlyAtDatabaseLevel() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = try SQLiteStore(url: folder.appendingPathComponent("test.sqlite"))
        try store.insert(AuditEvent(entityID: UUID(), event: "test"))
        XCTAssertThrowsError(try store.execute("DELETE FROM audit"))
        XCTAssertThrowsError(try store.execute("UPDATE audit SET entity_id='x'"))
    }
}
