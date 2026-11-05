import Foundation

public struct VietnameseVoiceParser: VoiceCommandParser {
    public init() {}
    public func parse(_ text: String, customers: [Customer], now: Date = Date()) -> VoiceDraft {
        let key = TextKey.normalize(text)
        let supplierName = supplierName(in: text)
        let supplier = supplierName != nil || key.contains("no tien hang")
        let mainAction = key.components(separatedBy: "da tra")[0]
        var intent: VoiceIntent = .unknown
        if key.contains("qua han") { intent = .overdue }
        else if key.contains("hom nay") && (key.contains("ai tra") || key.contains("thu duoc")) { intent = .todayCollections }
        else if key.contains("bao nhieu") || key.contains("tra cuu") || key.contains("xem no") { intent = supplier ? .supplierBalance : .balance }
        else if ["nhap hang", "lay hang tu", "lay hang cua", "tien nhap hang"].contains(where: key.contains) { intent = .purchase }
        else if mainAction.range(of: #"\b(?:tra|thanh toan)\s+(?:no\s+)?tien hang\b"#, options: .regularExpression) != nil { intent = .supplierPayment }
        else if key.contains("no tien hang") || supplier && key.contains("da tra") && key.components(separatedBy: "da tra")[0].range(of: #"\bno\b"#, options: .regularExpression) != nil { intent = .purchase }
        else if key.contains("tra tien hang") || key.contains("thanh toan tien hang") { intent = .supplierPayment }
        else if key.contains("thu no") { intent = .collection }
        else if key.range(of: #"\btra\b|\bthanh toan\b"#, options: .regularExpression) != nil { intent = supplier ? .supplierPayment : .collection }
        else if key.range(of: #"\b(?:ghi no|lay them|mua|no)\b"#, options: .regularExpression) != nil { intent = supplier || key.contains("no tien hang") ? .purchase : .debt }
        else if key.contains("them khach") || key.contains("tao khach") || key.contains("them xe") || key.contains("them nha cung cap") { intent = .createCustomer }
        else if key.contains("con no") { intent = .balance }
        var warnings: [String] = []
        var date = now
        if key.contains("hom qua") { date = VietnameseDate.calendar.date(byAdding: .day, value: -1, to: now)! }
        // Unimplemented date phrases must be corrected explicitly, never silently treated as today.
        if key.range(of: #"\d+[/\-]\d+|ngay mai|hom kia|tuan truoc|thang truoc"#, options: .regularExpression) != nil {
            warnings.append("Có ngày chưa phân tích được. Hãy chọn ngày giao dịch trước khi xác nhận.")
        }
        let book: AccountBook = [.purchase, .supplierPayment, .supplierBalance].contains(intent) ? .goods : .debt
        let available = customers.filter { AccountBook.inferred(for: $0) == book }
        let spokenName = newName(in: text) ?? personName(in: text)
        let candidates: [Customer]
        if let supplierName { candidates = CustomerMatcher.matchSupplier(supplierName, customers: available) }
        else if let spokenName { candidates = CustomerMatcher.matchPerson(spokenName, customers: available) }
        else { candidates = CustomerMatcher.match(text, customers: available) }
        if ![.todayCollections, .overdue, .createCustomer].contains(intent) && candidates.count != 1 {
            warnings.append(candidates.isEmpty ? "Chưa tìm thấy khách. Hãy chọn khách hàng." : "Có nhiều khách phù hợp. Hãy chọn đúng người.")
        }
        let parser = VietnameseMoneyParser()
        // Remove the captured business name before interpreting numeric money,
        // so a number in a supplier's name cannot become the transaction amount.
        let moneyText = supplierName.map { text.replacingOccurrences(of: $0, with: "", options: .caseInsensitive) } ?? text
        let spans = parser.spans(in: moneyText, allowBareVND: [.debt, .collection, .purchase, .supplierPayment].contains(intent))
        // Accent folding makes both “mới” and “mỗi” become “moi”.
        // Exclude the explicit new-customer phrase before checking unit prices.
        let pricingKey = key.replacingOccurrences(of: #"\b(?:them|tao)\s+khach\s+moi\b"#, with: "", options: .regularExpression)
        var amount: Int64?
        if spans.count == 1 {
            let result = parser.parse(spans[0]); amount = result.amount
            if let warning = result.warning { warnings.append(warning) }
            if pricingKey.range(of: #"\bmoi\b"#, options: .regularExpression) != nil {
                // Conservative support for explicit numeric quantities: “mua 5 bao … mỗi bao 90 nghìn”.
                if let regex = try? NSRegularExpression(pattern: #"\bmua\s+(\d+)\s+.+\bmoi\b"#),
                   let match = regex.firstMatch(in: pricingKey, range: NSRange(pricingKey.startIndex..., in: pricingKey)),
                   let range = Range(match.range(at: 1), in: pricingKey), let quantity = Int64(pricingKey[range]), quantity > 0, let unit = amount {
                    amount = try? CheckedMoney.multiply(unit, quantity)
                    if amount == nil { warnings.append("Thành tiền vượt giới hạn.") }
                } else { amount = nil; warnings.append("Chưa xác định đủ số lượng và đơn giá. Hãy nhập thành tiền.") }
            }
        } else if ![.balance, .supplierBalance, .todayCollections, .overdue, .createCustomer].contains(intent) {
            warnings.append("Cần một số tiền rõ ràng; nhiều khoản cần tách thành giao dịch riêng.")
        }
        var paidNow: Int64?
        if intent == .purchase, spans.count >= 1 {
            // Separate total and paid amounts by explicit labels, never sum unrelated money spans.
            let parts = TextKey.normalize(moneyText).components(separatedBy: "da tra")
            let totalSpans = parser.spans(in: parts[0], allowBareVND: true)
            if totalSpans.count == 1 { amount = parser.parse(totalSpans[0]).amount }
            if parts.count == 2 {
                let paymentText = parts[1].components(separatedBy: "con no")[0]
                let paid = parser.spans(in: paymentText, allowBareVND: true)
                if paymentText.trimmingCharacters(in: .whitespacesAndNewlines).range(of: #"^0(?:\s*(?:dong|vnd|d))?[.,]?$"#, options: .regularExpression) != nil { paidNow = 0 }
                else if paid.count == 1 {
                    paidNow = parser.parse(paid[0]).amount
                    if paidNow == nil { amount = nil; warnings.append("Phần đã trả chưa rõ số tiền.") }
                }
                else { amount = nil; warnings.append("Chưa rõ phần đã trả. Hãy nhập lại.") }
            } else if spans.count == 1 { paidNow = 0 }
            else { amount = nil }
            if let amount, let paidNow, paidNow > amount { warnings.append("Đã trả vượt tổng tiền hàng.") }
            warnings.removeAll { $0.hasPrefix("Cần một số tiền rõ ràng") }
        }
        if intent == .unknown { warnings.append("Chưa rõ yêu cầu. Hãy chọn loại giao dịch thủ công.") }
        var result = VoiceDraft(transcript: text, intent: intent, candidateIDs: candidates.map(\.id), amount: amount, effectiveDate: date, warnings: warnings)
        result.paidNow = paidNow
        if [.debt, .collection, .purchase].contains(intent) {
            let names = candidates.count == 1 ? [candidates[0].name, candidates[0].nickname] : []
            result.goodsDescription = goods(in: text, customerNames: names, debt: intent != .purchase)
            if intent == .purchase && result.goodsDescription == nil { result.goodsDescription = "Tiền hàng" }
        }
        if key.contains("them khach") || key.contains("tao khach") || key.contains("them xe") || key.contains("them nha cung cap") { result.newCustomerName = newName(in: text) }
        if candidates.isEmpty, [.debt, .collection, .purchase, .supplierPayment, .createCustomer].contains(intent),
           let name = supplierName ?? spokenName {
            result.newCustomerName = name
            result.warnings.removeAll { $0 == "Chưa tìm thấy khách. Hãy chọn khách hàng." }
        }
        if !candidates.isEmpty { result.newCustomerName = nil }
        return result
    }
    private func supplierName(in text: String) -> String? {
        guard let captured = capture(text, pattern: #"\b((?:nhà\s+xe|nha\s+xe|nhà\s+cung\s+cấp|nha\s+cung\s+cap|công\s+ty|cong\s+ty|xe)\s+[^\d\s,.;:!?][^,.;:!?]*?)(?=\s+(?:ghi\s+nợ|ghi\s+no|còn\s+nợ|con\s+no|nợ|no|trả|tra|đã\s+trả|da\s+tra|thanh\s+toán|thanh\s+toan|nhập\s+hàng|nhap\s+hang|mua|lấy|lay|gồm|gom|hàng\s+gồm|hang\s+gom|tổng|tong|thành\s+tiền|thanh\s+tien|số\s+điện\s+thoại|so\s+dien\s+thoai|hôm|hom|\d+(?:[.,]\d+)*)\b|[,.;:!?]|$)"#) else { return nil }
        guard let position = text.range(of: captured, options: .caseInsensitive) else { return nil }
        let prefix = TextKey.normalize(String(text[..<position.lowerBound])).trimmingCharacters(in: CharacterSet(charactersIn: ",.;:!? "))
        // Business cues belong to the contact clause, not to goods such as “bánh xe đạp”.
        guard prefix.isEmpty || prefix.range(of: #"^(?:ghi no|no|tra|thu|thanh toan|tra no tien hang|tra tien hang|nhap hang|lay hang|tien nhap hang|tra cuu no|tra cuu|xem no|them|tao)(?: tu| cua| cho)?$"#, options: .regularExpression) != nil else { return nil }
        if let mention = VietnameseMoneyParser().mentions(in: captured, allowBareVND: true).first,
           let range = Range(mention.range, in: captured) {
            let name = captured[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            return name.split(separator: " ").count >= 2 ? name : nil
        }
        return captured
    }
    private func personName(in input: String) -> String? {
        let text = input.precomposedStringWithCanonicalMapping
        guard let name = capture(text, pattern: #"^(.+?)\s+(?:vừa\s+|vua\s+|còn\s+|con\s+)?(?:ghi\s+nợ|ghi\s+no|nợ|no|trả|tra|thanh\s+toán|thanh\s+toan)\b"#),
              name.count <= 100, name.split(separator: " ").count <= 8,
              name.rangeOfCharacter(from: .decimalDigits) == nil,
              !AccountBook.hasSupplierCue(name),
              !["ghi", "thu", "tra cuu", "xem", "hom nay", "hom qua"].contains(TextKey.normalize(name)) else { return nil }
        return name.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.;:!?")))
    }

    private func newName(in text: String) -> String? {
        if let name = capture(text, pattern: #"(?:thêm|them|tạo|tao)\s+((?:xe|nhà\s+cung\s+cấp|nha\s+cung\s+cap|công\s+ty|cong\s+ty)\s+.+?)(?=\s+(?:ghi\s+nợ|ghi\s+no|nợ|no|nhập\s+hàng|nhap\s+hang|trả|tra|mua)|[,.;]|$)"#) { return name }
        // Fold only for matching, retaining accents in the captured display name.
        return capture(text, pattern: #"(?:thêm|them|tạo|tao)\s+khách(?:\s+mới)?\s+(.+?)(?=\s+(?:ghi\s+nợ|nợ|nhập\s+hàng|trả|mua)|[,.;]|$)"#)
        ?? capture(text, pattern: #"(?:them|tao)\s+khach(?:\s+moi)?\s+(.+?)(?=\s+(?:ghi\s+no|no|nhap\s+hang|tra|mua)|[,.;]|$)"#)
    }
    private func goods(in input: String, customerNames: [String], debt: Bool) -> String? {
        let text = input.precomposedStringWithCanonicalMapping
        let explicit = capture(text, pattern: #"(?:mặt\s+hàng|hàng\s+gồm|gồm|mat\s+hang|hang\s+gom|gom)\s+(.+)$"#)
        let debtClause = debt ? capture(text, pattern: #"(?:ghi\s+nợ|ghi\s+no|nợ|no|trả|tra|thanh\s+toán|thanh\s+toan|mua|lấy\s+thêm|lay\s+them)\s+(.+)$"#) : nil
        guard var clause = explicit ?? debtClause else { return nil }
        for name in customerNames.filter({ !$0.isEmpty }).sorted(by: { $0.count > $1.count }) {
            if let range = clause.range(of: name, options: [.anchored, .caseInsensitive, .diacriticInsensitive]),
               range.upperBound == clause.endIndex || clause[range.upperBound].isWhitespace {
                clause = String(clause[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        if let money = VietnameseMoneyParser().mentions(in: clause, allowBareVND: true).first,
           let range = Range(money.range, in: clause) { clause = String(clause[..<range.lowerBound]) }
        clause = clause.replacingOccurrences(of: #"\s+(?:mỗi|moi)\b.*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        clause = clause.replacingOccurrences(of: #"\b(?:tổng(?:\s+tiền(?:\s+hàng)?)?|tong(?:\s+tien(?:\s+hang)?)?|thành\s+tiền|thanh\s+tien|số\s+tiền|so\s+tien|giá|gia|hết|het)\s*[:=]?\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        clause = clause.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.;:=-")))
        if ["tien hang", "hang", "tien", "tien no"].contains(TextKey.normalize(clause)) { return nil }
        return clause.isEmpty ? nil : clause
    }
    private func capture(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        let result = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}
public enum CustomerMatcher {
    public static func matchPerson(_ name: String, customers: [Customer]) -> [Customer] {
        func key(_ value: String) -> String {
            TextKey.normalize(value).replacingOccurrences(of: #"^(?:anh|chi|co|chu|bac|ong|ba|em)\s+"#, with: "", options: .regularExpression)
        }
        let target = key(name)
        let exact = customers.filter { customer in
            customer.mergedInto == nil && [customer.name, customer.nickname].contains { !key($0).isEmpty && key($0) == target }
        }
        if !exact.isEmpty { return exact }
        // A spoken full name must not silently select someone sharing its last word.
        return target.split(separator: " ").count == 1 ? match(name, customers: customers) : []
    }
    public static func matchSupplier(_ name: String, customers: [Customer]) -> [Customer] {
        let exact = customers.filter { customer in
            customer.mergedInto == nil && [customer.name, customer.nickname].contains { TextKey.normalize($0) == TextKey.normalize(name) }
        }
        if !exact.isEmpty { return exact }
        func key(_ value: String) -> String {
            TextKey.normalize(value).replacingOccurrences(of: #"^(?:nha xe|nha cung cap|cong ty|xe)\s+"#, with: "", options: .regularExpression)
        }
        let target = key(name)
        return customers.filter { customer in
            customer.mergedInto == nil && [customer.name, customer.nickname].contains { !key($0).isEmpty && key($0) == target }
        }
    }
    public static func match(_ text: String, customers: [Customer]) -> [Customer] {
        let key = " " + TextKey.normalize(text).replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression) + " "
        let available = customers.filter { $0.mergedInto == nil }
        let full = available.filter { customer in
            [customer.name, customer.nickname].contains { candidate in
                let name = TextKey.normalize(candidate)
                return !name.isEmpty && key.contains(" " + name + " ")
            }
        }
        if !full.isEmpty { return full }
        return available.filter { customer in
            guard let last = TextKey.normalize(customer.name).split(separator: " ").last else { return false }
            return key.contains(" " + last + " ")
        }
    }
}
