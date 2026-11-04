import Foundation

public struct OCRRow: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var attachmentID: UUID
    public var rawText: String
    public var customerName: String
    public var customerID: UUID?
    public var amount: Int64?
    public var kind: TransactionKind
    public var date: Date
    public var note: String
    public var warning: String?
    public var confirmed: Bool
    public var quantity: Int64?
    public var unitPrice: Int64?
    public init(id: UUID = UUID(), attachmentID: UUID, rawText: String, customerName: String = "", customerID: UUID? = nil, amount: Int64? = nil, kind: TransactionKind = .debt, date: Date, note: String = "", warning: String? = nil, confirmed: Bool = false, quantity: Int64? = nil, unitPrice: Int64? = nil) {
        self.id = id; self.attachmentID = attachmentID; self.rawText = rawText; self.customerName = customerName
        self.customerID = customerID; self.amount = amount; self.kind = kind; self.date = date
        self.note = note; self.warning = warning; self.confirmed = confirmed; self.quantity = quantity; self.unitPrice = unitPrice
    }
    public func transaction() throws -> DebtTransaction {
        guard confirmed, let customerID, let amount, amount > 0, kind != .reversal else { throw LedgerError.invalid("Mỗi dòng nhập phải có khách, ngày, số tiền và được xác nhận.") }
        if quantity != nil || unitPrice != nil {
            guard let quantity, let unitPrice, quantity > 0, unitPrice > 0,
                  try CheckedMoney.multiply(quantity, unitPrice) == amount else { throw LedgerError.invalid("Số lượng × đơn giá không bằng thành tiền. Hãy sửa lại.") }
        }
        return DebtTransaction(customerID: customerID, amount: amount, kind: kind, effectiveDate: date, note: note, source: .ocr, attachmentIDs: [attachmentID], importKey: "ocr:\(attachmentID.uuidString):\(id.uuidString)", goodsDescription: kind == .purchase ? (note.isEmpty ? rawText : note) : nil)
    }
}

public struct NotebookParser: Sendable {
    public init() {}
    /// Printed OCR text is only a proposal. Missing year is an explicit review warning.
    public func parse(_ text: String, attachmentID: UUID, customers: [Customer], referenceDate: Date = Date()) -> [OCRRow] {
        var customerName = "", rows: [OCRRow] = []
        let calendar = VietnameseDate.calendar
        let year = calendar.component(.year, from: referenceDate)
        guard let dateRegex = try? NSRegularExpression(pattern: #"^(\d{1,2})[/.](\d{1,2})(?:[/.](\d{4}))?\s*[:\-]?\s*(.*)$"#) else { return [] }
        for line in text.components(separatedBy: .newlines).map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !line.isEmpty {
            guard let match = dateRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
                if line.rangeOfCharacter(from: .decimalDigits) == nil { customerName = line }
                else { rows.append(OCRRow(attachmentID: attachmentID, rawText: line, customerName: customerName, date: referenceDate, warning: "Không tách được ngày/số tiền. Hãy nhập lại đầy đủ.")) }
                continue
            }
            func capture(_ index: Int) -> String? { Range(match.range(at: index), in: line).map { String(line[$0]) } }
            let day = Int(capture(1) ?? "") ?? 0, month = Int(capture(2) ?? "") ?? 0
            let explicitYear = capture(3).flatMap(Int.init)
            let components = DateComponents(year: explicitYear ?? year, month: month, day: day, hour: 12)
            let parsedDate = calendar.date(from: components)
            let validDate = parsedDate.map { calendar.component(.day, from: $0) == day && calendar.component(.month, from: $0) == month } ?? false
            let body = capture(4) ?? ""
            let key = TextKey.normalize(body)
            let kind: TransactionKind = key.contains("tra") || key.contains("thu") ? .collection : .debt
            let moneyText = key.replacingOccurrences(of: "tra", with: "").replacingOccurrences(of: "thu", with: "").trimmingCharacters(in: .whitespaces)
            let money = VietnameseMoneyParser().parse(moneyText)
            let matches = CustomerMatcher.match(customerName, customers: customers)
            var warnings = [String]()
            if explicitYear == nil { warnings.append("Thiếu năm; đang đề xuất năm \(year).") }
            if !validDate { warnings.append("Ngày không hợp lệ.") }
            if let warning = money.warning { warnings.append(warning) }
            if matches.count != 1 { warnings.append("Cần chọn khách hàng.") }
            rows.append(OCRRow(attachmentID: attachmentID, rawText: line, customerName: customerName, customerID: matches.count == 1 ? matches[0].id : nil,
                               amount: money.amount, kind: kind, date: validDate ? parsedDate! : referenceDate, warning: warnings.isEmpty ? nil : warnings.joined(separator: " ")))
        }
        return rows
    }
}
