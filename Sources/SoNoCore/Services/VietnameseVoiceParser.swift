import Foundation

public struct VietnameseVoiceParser: VoiceCommandParser {
    public init() {}
    public func parse(_ text: String, customers: [Customer], now: Date = Date()) -> VoiceDraft {
        let key = TextKey.normalize(text)
        var intent: VoiceIntent = .unknown
        if key.contains("qua han") { intent = .overdue }
        else if key.contains("hom nay") && (key.contains("ai tra") || key.contains("thu duoc")) { intent = .todayCollections }
        else if key.contains("bao nhieu") || key.contains("tra cuu") || key.contains("xem no") { intent = .balance }
        else if ["nhap hang", "lay hang tu", "lay hang cua", "tien nhap hang"].contains(where: key.contains) { intent = .purchase }
        else if key.contains("tra tien hang") || key.contains("thanh toan tien hang") { intent = .supplierPayment }
        else if key.range(of: #"\btra\b|\bthanh toan\b"#, options: .regularExpression) != nil { intent = .collection }
        else if ["ghi no", "lay them", "mua", "no them", " no "].contains(where: key.contains) { intent = .debt }
        else if key.contains("them khach") || key.contains("tao khach") { intent = .createCustomer }
        else if key.contains("con no") { intent = .balance }
        var warnings: [String] = []
        var date = now
        if key.contains("hom qua") { date = VietnameseDate.calendar.date(byAdding: .day, value: -1, to: now)! }
        // Unimplemented date phrases must be corrected explicitly, never silently treated as today.
        if key.range(of: #"\d+[/\-]\d+|ngay mai|hom kia|tuan truoc|thang truoc"#, options: .regularExpression) != nil {
            warnings.append("Có ngày chưa phân tích được. Hãy chọn ngày giao dịch trước khi xác nhận.")
        }
        let candidates = CustomerMatcher.match(text, customers: customers)
        if ![.todayCollections, .overdue, .createCustomer].contains(intent) && candidates.count != 1 {
            warnings.append(candidates.isEmpty ? "Chưa tìm thấy khách. Hãy chọn khách hàng." : "Có nhiều khách phù hợp. Hãy chọn đúng người.")
        }
        let parser = VietnameseMoneyParser()
        let spans = parser.spans(in: text)
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
        } else if ![.balance, .todayCollections, .overdue, .createCustomer].contains(intent) {
            warnings.append("Cần một số tiền rõ ràng có đơn vị; nhiều khoản cần tách thành giao dịch riêng.")
        }
        var paidNow: Int64?
        if intent == .purchase, spans.count >= 1 {
            // Separate total and paid amounts by explicit labels, never sum unrelated money spans.
            let parts = key.components(separatedBy: "da tra")
            let totalSpans = parser.spans(in: parts[0])
            if totalSpans.count == 1 { amount = parser.parse(totalSpans[0]).amount }
            if parts.count == 2 {
                let paymentText = parts[1].components(separatedBy: "con no")[0]
                let paid = parser.spans(in: paymentText)
                if paid.count == 1 {
                    paidNow = parser.parse(paid[0]).amount
                    if paidNow == nil { amount = nil; warnings.append("Phần đã trả chưa rõ số tiền.") }
                }
                else if paymentText.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("0") { paidNow = 0 }
                else { amount = nil; warnings.append("Chưa rõ phần đã trả. Hãy nhập lại.") }
            } else if spans.count == 1 { paidNow = 0 }
            else { amount = nil }
            if let amount, let paidNow, paidNow > amount { warnings.append("Đã trả vượt tổng tiền hàng.") }
            warnings.removeAll { $0.hasPrefix("Cần một số tiền rõ ràng") }
        }
        if intent == .unknown { warnings.append("Chưa rõ yêu cầu. Hãy chọn loại giao dịch thủ công.") }
        var result = VoiceDraft(transcript: text, intent: intent, candidateIDs: candidates.map(\.id), amount: amount, effectiveDate: date, warnings: warnings)
        result.paidNow = paidNow
        if intent == .purchase { result.goodsDescription = goods(in: text) }
        if key.contains("them khach") || key.contains("tao khach") { result.newCustomerName = newName(in: text) }
        return result
    }
    private func newName(in text: String) -> String? {
        // Fold only for matching, retaining accents in the captured display name.
        capture(text, pattern: #"(?:thêm|them|tạo|tao)\s+khách(?:\s+mới)?\s+(.+?)(?=\s+(?:ghi\s+nợ|nợ|nhập\s+hàng|trả|mua)|[,.;]|$)"#)
        ?? capture(text, pattern: #"(?:them|tao)\s+khach(?:\s+moi)?\s+(.+?)(?=\s+(?:ghi\s+no|no|nhap\s+hang|tra|mua)|[,.;]|$)"#)
    }
    private func goods(in text: String) -> String? {
        capture(text, pattern: #"(?:mặt\s+hàng|hàng\s+gồm|gồm|mat\s+hang|hang\s+gom|gom)\s+(.+?)(?=\s+(?:tổng|thành\s+tiền|giá|tong|thanh\s+tien|gia)|[,.;]|$)"#)
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
