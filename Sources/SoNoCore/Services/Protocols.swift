import Foundation

public protocol CustomerRepository: Sendable {
    func saveCustomer(_ customer: Customer, allowDuplicate: Bool) async throws
    func mergeCustomer(_ sourceID: UUID, into targetID: UUID, confirmed: Bool) async throws
}
public protocol DebtRepository: Sendable {
    func balance(customerID: UUID) async throws -> Balance
}
public protocol TransactionRepository: Sendable {
    func post(_ entries: [DebtTransaction], attachments: [Attachment], confirmed: Bool, allowDuplicate: Bool) async throws
    func reverse(_ id: UUID, reason: String) async throws
}
public protocol AuditLogRepository: Sendable { func snapshot() async throws -> LedgerSnapshot }
public protocol VoiceCommandParser: Sendable {
    func parse(_ text: String, customers: [Customer], now: Date) -> VoiceDraft
}
public protocol HandwritingOCRService: Sendable {
    func recognize(_ image: Data) async throws -> String
}
public protocol BackupService: Sendable {
    func export(password: String?) async throws -> Data
    func restore(_ data: Data, password: String?, confirmed: Bool) async throws
}
public protocol ReminderService: Sendable {
    func synchronize(snapshot: LedgerSnapshot) async throws
}
public enum VoiceIntent: String, Codable, Sendable { case debt, collection, balance, todayCollections, overdue, unknown }
public struct VoiceDraft: Codable, Sendable {
    public var transcript: String
    public var intent: VoiceIntent
    public var candidateIDs: [UUID]
    public var amount: Int64?
    public var effectiveDate: Date
    public var warnings: [String]
    public var isQuery: Bool { [.balance, .todayCollections, .overdue].contains(intent) }
}
