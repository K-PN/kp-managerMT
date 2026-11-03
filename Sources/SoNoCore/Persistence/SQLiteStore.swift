import Foundation
import CSQLite

/// Access is confined to LedgerService's actor. Never pass this connection to a View.
final class SQLiteStore {
    private var connection: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    enum Value { case text(String), integer(Int64), real(Double), blob(Data), null }
    init(url: URL) throws {
        guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let connection { sqlite3_close(connection) }; connection = nil
            throw LedgerError.storage("Không thể mở cơ sở dữ liệu. Không tạo dữ liệu thay thế.")
        }
        do {
            sqlite3_busy_timeout(connection, 5_000)
            try execute("PRAGMA foreign_keys = ON")
            try execute("PRAGMA journal_mode = WAL")
            try execute("PRAGMA synchronous = FULL")
            let version = Int(try scalar("PRAGMA user_version")) ?? -1
            guard version >= 0 && version <= 1 else { throw LedgerError.unsupportedSchema }
            if version == 0 {
                guard let migration = Bundle.module.url(forResource: "001_initial", withExtension: "sql", subdirectory: "Migrations") else {
                    throw LedgerError.storage("Thiếu tệp migration.")
                }
                let sql = try String(contentsOf: migration, encoding: .utf8)
                try transaction { try execute(sql); try execute("PRAGMA user_version = 1") }
            }
            guard try scalar("PRAGMA quick_check") == "ok" else { throw LedgerError.storage("Cơ sở dữ liệu cần kiểm tra tính toàn vẹn.") }
        } catch { sqlite3_close(connection); connection = nil; throw error }
    }
    deinit { sqlite3_close(connection) }
    func execute(_ sql: String) throws {
        guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }
    func transaction<T>(_ work: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do { let value = try work(); try execute("COMMIT"); return value }
        catch { try? execute("ROLLBACK"); throw error }
    }
    private func failure() -> LedgerError { .storage("Không thể ghi/đọc dữ liệu (SQLite \(sqlite3_extended_errcode(connection))). Thao tác chưa hoàn tất.") }
    private func prepare(_ sql: String, _ values: [Value]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure() }
        do {
            for (offset, value) in values.enumerated() {
                let index = Int32(offset + 1), result: Int32
                switch value {
                case .text(let text): result = sqlite3_bind_text(statement, index, text, -1, transient)
                case .integer(let integer): result = sqlite3_bind_int64(statement, index, integer)
                case .real(let number): result = sqlite3_bind_double(statement, index, number)
                case .blob(let data): result = data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(data.count), transient) }
                case .null: result = sqlite3_bind_null(statement, index)
                }
                guard result == SQLITE_OK else { throw failure() }
            }
            return statement
        } catch { sqlite3_finalize(statement); throw error }
    }
    func run(_ sql: String, _ values: [Value] = []) throws {
        let statement = try prepare(sql, values); defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }
    func scalar(_ sql: String) throws -> String {
        let statement = try prepare(sql, []); defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else { throw failure() }
        return String(cString: value)
    }
    private func read<T: Decodable>(_ table: String) throws -> [T] {
        let statement = try prepare("SELECT payload FROM \(table) ORDER BY rowid", []); defer { sqlite3_finalize(statement) }
        var result: [T] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return result }
            guard step == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { throw failure() }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
            result.append(try JSONDecoder().decode(T.self, from: data))
        }
    }
    func snapshot() throws -> LedgerSnapshot {
        var result = LedgerSnapshot()
        result.customers = try read("customers"); result.transactions = try read("transactions")
        result.audit = try read("audit"); result.attachments = try read("attachments"); result.drafts = try read("drafts")
        return result
    }
    func save(_ customer: Customer) throws {
        try run("INSERT INTO customers(id,search_key,payload) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET search_key=excluded.search_key,payload=excluded.payload", [.text(customer.id.uuidString), .text(TextKey.normalize(customer.name + " " + customer.nickname + " " + customer.phone)), .blob(try JSONCoding.encode(customer))])
    }
    func insert(_ entry: DebtTransaction) throws {
        try run("INSERT INTO transactions(id,customer_id,amount,effective_date,kind,reversal_of,import_key,payload) VALUES(?,?,?,?,?,?,?,?)", [
            .text(entry.id.uuidString), .text(entry.customerID.uuidString), .integer(entry.amount), .real(entry.effectiveDate.timeIntervalSince1970), .text(entry.kind.rawValue),
            entry.reversalOf.map { .text($0.uuidString) } ?? .null, entry.importKey.map { .text($0) } ?? .null, .blob(try JSONCoding.encode(entry))])
    }
    func insert(_ event: AuditEvent) throws {
        try run("INSERT INTO audit(id,entity_id,timestamp,payload) VALUES(?,?,?,?)", [.text(event.id.uuidString), .text(event.entityID.uuidString), .real(event.timestamp.timeIntervalSince1970), .blob(try JSONCoding.encode(event))])
    }
    func insert(_ attachment: Attachment) throws {
        try run("INSERT INTO attachments(id,payload) VALUES(?,?)", [.text(attachment.id.uuidString), .blob(try JSONCoding.encode(attachment))])
    }
    func save(_ draft: SavedDraft) throws {
        try run("INSERT INTO drafts(id,payload) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload", [.text(draft.id.uuidString), .blob(try JSONCoding.encode(draft))])
    }
    func deleteDraft(_ id: UUID) throws { try run("DELETE FROM drafts WHERE id=?", [.text(id.uuidString)]) }
    func loadDraft(_ id: UUID) throws -> SavedDraft? {
        let statement = try prepare("SELECT payload FROM drafts WHERE id=?", [.text(id.uuidString)])
        defer { sqlite3_finalize(statement) }
        let step = sqlite3_step(statement)
        if step == SQLITE_DONE { return nil }
        guard step == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { throw failure() }
        return try JSONDecoder().decode(SavedDraft.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0))))
    }
    func replace(with snapshot: LedgerSnapshot, existingAudit: [AuditEvent]) throws {
        // All statements, including the restore event, are called inside one transaction.
        try execute("DELETE FROM transactions; DELETE FROM customers; DELETE FROM attachments; DELETE FROM drafts;")
        for customer in snapshot.customers { try save(customer) }
        for attachment in snapshot.attachments { try insert(attachment) }
        for entry in snapshot.transactions.filter({ $0.kind != .reversal }) { try insert(entry) }
        for entry in snapshot.transactions.filter({ $0.kind == .reversal }) { try insert(entry) }
        let existingIDs = Set(existingAudit.map(\.id))
        for event in snapshot.audit where !existingIDs.contains(event.id) { try insert(event) }
        for draft in snapshot.drafts { try save(draft) }
    }
}
