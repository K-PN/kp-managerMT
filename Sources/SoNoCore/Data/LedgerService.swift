import Foundation

public actor LedgerService: CustomerRepository, DebtRepository, TransactionRepository, AuditLogRepository {
    private let store: SQLiteStore
    public init(databaseURL: URL) throws { store = try SQLiteStore(url: databaseURL) }
    public func snapshot() throws -> LedgerSnapshot { try store.snapshot() }
    public func balance(customerID: UUID) throws -> Balance {
        try LedgerCalculator.balance(store.snapshot().entries(for: customerID))
    }
    public func saveCustomer(_ customer: Customer, allowDuplicate: Bool = false) throws {
        var value = customer
        value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.name.isEmpty, value.name.count <= 200, value.note.count <= 10_000 else { throw LedgerError.invalid("Tên khách không được trống hoặc quá dài.") }
        try store.transaction {
            let state = try store.snapshot()
            let old = state.customers.first { $0.id == value.id }
            guard old?.mergedInto == nil, value.mergedInto == nil else { throw LedgerError.invalid("Khách này đã được gộp.") }
            let changesName = old.map { TextKey.normalize($0.name) != TextKey.normalize(value.name) } ?? true
            if changesName && !allowDuplicate && state.customers.contains(where: { $0.id != value.id && $0.mergedInto == nil && TextKey.normalize($0.name) == TextKey.normalize(value.name) }) { throw LedgerError.duplicateCustomer }
            value.createdAt = old?.createdAt ?? Date(); value.updatedAt = Date()
            try store.save(value)
            try store.insert(AuditEvent(entityID: value.id, event: old == nil ? "Tạo khách hàng" : "Sửa khách hàng", oldValue: try old.map(JSONCoding.string), newValue: try JSONCoding.string(value)))
        }
    }
    public func mergeCustomer(_ sourceID: UUID, into targetID: UUID, confirmed: Bool) throws {
        guard confirmed, sourceID != targetID else { throw LedgerError.invalid("Cần xác nhận gộp hai khách khác nhau.") }
        try store.transaction {
            var state = try store.snapshot()
            guard let index = state.customers.firstIndex(where: { $0.id == sourceID && $0.mergedInto == nil }),
                  state.customers.contains(where: { $0.id == targetID && $0.mergedInto == nil }) else { throw LedgerError.notFound }
            let old = state.customers[index]
            state.customers[index].mergedInto = targetID; state.customers[index].updatedAt = Date()
            _ = try LedgerCalculator.balance(state.entries(for: targetID))
            try store.save(state.customers[index])
            try store.insert(AuditEvent(entityID: sourceID, event: "Gộp khách hàng", oldValue: try JSONCoding.string(old), newValue: try JSONCoding.string(state.customers[index]), reason: "Đã xác nhận gộp vào \(targetID)"))
        }
    }
    public func post(_ entries: [DebtTransaction], attachments: [Attachment] = [], confirmed: Bool, allowDuplicate: Bool = false) throws {
        try commit(entries, attachments: attachments, confirmed: confirmed, allowDuplicate: allowDuplicate, newCustomer: nil)
    }
    public func confirm(_ proposal: TransactionProposal, attachments: [Attachment] = [], confirmed: Bool) throws {
        try commit(proposal.entries, attachments: attachments, confirmed: confirmed, allowDuplicate: false, newCustomer: proposal.newCustomer)
    }
    private func commit(_ entries: [DebtTransaction], attachments: [Attachment], confirmed: Bool, allowDuplicate: Bool, newCustomer: Customer?) throws {
        guard confirmed, !entries.isEmpty else { throw LedgerError.invalid("Cần xác nhận trước khi ghi sổ.") }
        try store.transaction {
            var state = try store.snapshot()
            if var customer = newCustomer {
                customer.name = customer.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !customer.name.isEmpty, customer.name.count <= 200, customer.mergedInto == nil,
                      entries.allSatisfy({ $0.customerID == customer.id }) else { throw LedgerError.invalid("Khách mới không hợp lệ.") }
                guard !state.customers.contains(where: { $0.id == customer.id || $0.mergedInto == nil && TextKey.normalize($0.name) == TextKey.normalize(customer.name) }) else { throw LedgerError.duplicateCustomer }
                try store.save(customer)
                try store.insert(AuditEvent(entityID: customer.id, event: "Tạo khách hàng", newValue: try JSONCoding.string(customer), source: entries[0].source))
                state.customers.append(customer)
            }
            guard !entries.contains(where: { $0.kind == .reversal || $0.reversalOf != nil }) else { throw LedgerError.invalid("Dùng chức năng hoàn tác để giữ lịch sử.") }
            guard attachments.allSatisfy({ !$0.data.isEmpty && $0.data.count <= 20_000_000 }) else { throw LedgerError.invalid("Mỗi ảnh phải nhỏ hơn 20 MB.") }
            let allAttachments = state.attachments + attachments
            guard Set(allAttachments.map(\.id)).count == allAttachments.count else { throw LedgerError.invalid("UUID ảnh bị trùng.") }
            let ids = Set(allAttachments.map(\.id))
            for entry in entries {
                guard state.customers.contains(where: { $0.id == entry.customerID && $0.mergedInto == nil }) else { throw LedgerError.notFound }
                guard entry.amount > 0, entry.note.count <= 10_000, entry.effectiveDate <= Date().addingTimeInterval(60),
                      entry.attachmentIDs.allSatisfy(ids.contains) else { throw LedgerError.invalid("Số tiền, ảnh hoặc ngày giao dịch không hợp lệ. Ngày đến hạn có thể ở tương lai.") }
                if entry.kind == .purchase {
                    guard let goods = entry.goodsDescription, !goods.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, goods.count <= 10_000 else { throw LedgerError.invalid("Cần tên mặt hàng hợp lệ.") }
                }
                if let due = entry.dueDate, due < VietnameseDate.calendar.startOfDay(for: entry.effectiveDate) { throw LedgerError.invalid("Hạn trả không được trước ngày giao dịch.") }
                if [.adjustmentIncrease, .adjustmentDecrease].contains(entry.kind) && entry.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw LedgerError.invalid("Điều chỉnh cần lý do.") }
                if state.transactions.contains(where: { $0.id == entry.id || (entry.importKey != nil && $0.importKey == entry.importKey) }) { throw LedgerError.duplicateTransaction }
                if entry.source == .ocr && !allowDuplicate && state.transactions.contains(where: {
                    $0.customerID == entry.customerID && $0.amount == entry.amount && $0.kind == entry.kind && VietnameseDate.calendar.isDate($0.effectiveDate, inSameDayAs: entry.effectiveDate)
                }) { throw LedgerError.duplicateTransaction }
                state.transactions.append(entry)
            }
            for customerID in Set(entries.map(\.customerID)) { _ = try LedgerCalculator.balance(state.entries(for: customerID)) }
            for attachment in attachments { try store.insert(attachment) }
            for entry in entries {
                try store.insert(entry)
                try store.insert(AuditEvent(entityID: entry.id, event: entry.source == .ocr ? "Nhập OCR: \(entry.kind.title)" : entry.kind.title, newValue: try JSONCoding.string(entry), source: entry.source, reason: entry.note))
            }
        }
    }
    public func reverse(_ id: UUID, reason: String) throws { try correct(id, replacement: nil, reason: reason) }
    /// Atomic reversal + replacement; originals are never overwritten.
    public func correct(_ id: UUID, replacement: DebtTransaction?, reason: String) throws {
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LedgerError.invalid("Cần lý do hoàn tác/điều chỉnh.") }
        try store.transaction {
            var state = try store.snapshot()
            guard let old = state.transactions.first(where: { $0.id == id && $0.kind != .reversal }),
                  !state.transactions.contains(where: { $0.reversalOf == id }) else { throw LedgerError.notFound }
            let reversal = DebtTransaction(customerID: old.customerID, amount: old.amount, kind: .reversal, note: reason, reversalOf: old.id)
            state.transactions.append(reversal)
            if let replacement {
                guard replacement.customerID == old.customerID, replacement.kind != .reversal,
                      replacement.reversalOf == nil, replacement.amount > 0, replacement.id != old.id,
                      !state.transactions.contains(where: { $0.id == replacement.id }),
                      replacement.effectiveDate <= Date(), replacement.importKey == nil,
                      replacement.attachmentIDs.allSatisfy({ id in state.attachments.contains { $0.id == id } }) else { throw LedgerError.invalid("Giao dịch thay thế không hợp lệ.") }
                if let due = replacement.dueDate, due < VietnameseDate.calendar.startOfDay(for: replacement.effectiveDate) { throw LedgerError.invalid("Hạn trả không hợp lệ.") }
                if replacement.kind == .purchase && (replacement.goodsDescription?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) { throw LedgerError.invalid("Cần tên mặt hàng.") }
                state.transactions.append(replacement)
            }
            _ = try LedgerCalculator.balance(state.entries(for: old.customerID))
            try store.insert(reversal)
            try store.insert(AuditEvent(entityID: reversal.id, event: "Hoàn tác giao dịch", oldValue: try JSONCoding.string(old), newValue: try JSONCoding.string(reversal), reason: reason))
            if let replacement {
                try store.insert(replacement)
                try store.insert(AuditEvent(entityID: replacement.id, event: "Giao dịch thay thế", oldValue: try JSONCoding.string(old), newValue: try JSONCoding.string(replacement), reason: reason))
            }
        }
    }
    public func saveDraft(_ draft: SavedDraft) throws { try store.transaction { try store.save(draft) } }
    public func loadDraft(_ id: UUID) throws -> SavedDraft? { try store.loadDraft(id) }
    public func deleteDraft(_ id: UUID) throws { try store.transaction { try store.deleteDraft(id) } }
    public func restoreSnapshot(_ replacement: LedgerSnapshot, confirmed: Bool) throws {
        guard confirmed else { throw LedgerError.invalid("Cần xác nhận thay dữ liệu bằng bản sao lưu.") }
        try SnapshotValidator.validate(replacement)
        try store.transaction {
            let old = try store.snapshot()
            let oldEvents = Dictionary(uniqueKeysWithValues: old.audit.map { ($0.id, $0) })
            guard replacement.audit.allSatisfy({ oldEvents[$0.id] == nil || oldEvents[$0.id] == $0 }) else { throw LedgerError.corruptBackup }
            try store.replace(with: replacement, existingAudit: old.audit)
            try store.insert(AuditEvent(entityID: UUID(), event: "Khôi phục sao lưu", oldValue: "\(old.customers.count) khách; \(old.transactions.count) giao dịch", newValue: "\(replacement.customers.count) khách; \(replacement.transactions.count) giao dịch", source: .restore, reason: "Người dùng xác nhận. Giữ lại nhật ký trước khôi phục."))
        }
    }
}

public enum SnapshotValidator {
    public static func validate(_ state: LedgerSnapshot) throws {
        guard state.schemaVersion == 1 else { throw LedgerError.unsupportedSchema }
        guard Set(state.customers.map(\.id)).count == state.customers.count,
              Set(state.audit.map(\.id)).count == state.audit.count,
              Set(state.attachments.map(\.id)).count == state.attachments.count,
              Set(state.drafts.map(\.id)).count == state.drafts.count,
              state.customers.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              state.attachments.allSatisfy({ !$0.data.isEmpty && $0.data.count <= 20_000_000 }) else { throw LedgerError.corruptBackup }
        let keys = state.transactions.compactMap(\.importKey)
        guard Set(keys).count == keys.count else { throw LedgerError.corruptBackup }
        let customerIDs = Set(state.customers.map(\.id)), attachmentIDs = Set(state.attachments.map(\.id)), audited = Set(state.audit.map(\.entityID))
        guard state.transactions.allSatisfy({ customerIDs.contains($0.customerID) && $0.attachmentIDs.allSatisfy(attachmentIDs.contains) && audited.contains($0.id) }),
              state.customers.allSatisfy({ audited.contains($0.id) }) else { throw LedgerError.corruptBackup }
        guard state.transactions.filter({ $0.kind == .purchase }).allSatisfy({ !($0.goodsDescription?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }) else { throw LedgerError.corruptBackup }
        // Validate all UUIDs together, including reversals that might otherwise cross customer ledgers.
        _ = try LedgerCalculator.active(state.transactions)
        let index = try LedgerIndex(snapshot: state)
        for entries in index.entriesByRoot.values {
            _ = try LedgerCalculator.balance(entries)
        }
    }
}
