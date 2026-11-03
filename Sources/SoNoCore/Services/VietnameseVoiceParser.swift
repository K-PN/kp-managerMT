import Foundation

public struct VietnameseVoiceParser: VoiceCommandParser {
    public init() {}
    public func parse(_ text: String, customers: [Customer], now: Date = Date()) -> VoiceDraft {
        let key = TextKey.normalize(text)
        var intent: VoiceIntent = .unknown
        if key.contains("qua han") { intent = .overdue }
        else if key.contains("hom nay") && (key.contains("ai tra") || key.contains("thu duoc")) { intent = .todayCollections }
        else if key.contains("bao nhieu") || key.contains("con no") { intent = .balance }
        else if key.contains("tra") || key.contains("thanh toan") { intent = .collection }
        else if ["ghi no", "lay them", "mua", "no them"].contains(where: key.contains) { intent = .debt }
        var warnings: [String] = []
        var date = now
        if key.contains("hom qua") { date = VietnameseDate.calendar.date(byAdding: .day, value: -1, to: now)! }
        // Unimplemented date phrases must be corrected explicitly, never silently treated as today.
        if key.range(of: #"\d+[/\-]\d+|ngay mai|hom kia|tuan truoc|thang truoc"#, options: .regularExpression) != nil {
            warnings.append("Có ngày chưa phân tích được. Hãy chọn ngày giao dịch trước khi xác nhận.")
        }
        let candidates = CustomerMatcher.match(text, customers: customers)
        if ![.todayCollections, .overdue].contains(intent) && candidates.count != 1 {
            warnings.append(candidates.isEmpty ? "Chưa tìm thấy khách. Hãy chọn khách hàng." : "Có nhiều khách phù hợp. Hãy chọn đúng người.")
        }
        let parser = VietnameseMoneyParser()
        let spans = parser.spans(in: text)
        var amount: Int64?
        if spans.count == 1 {
            let result = parser.parse(spans[0]); amount = result.amount
            if let warning = result.warning { warnings.append(warning) }
            if key.contains("moi") {
                // Conservative support for explicit numeric quantities: “mua 5 bao … mỗi bao 90 nghìn”.
                if let regex = try? NSRegularExpression(pattern: #"\bmua\s+(\d+)\s+.+\bmoi\b"#),
                   let match = regex.firstMatch(in: key, range: NSRange(key.startIndex..., in: key)),
                   let range = Range(match.range(at: 1), in: key), let quantity = Int64(key[range]), quantity > 0, let unit = amount {
                    amount = try? CheckedMoney.multiply(unit, quantity)
                    if amount == nil { warnings.append("Thành tiền vượt giới hạn.") }
                } else { amount = nil; warnings.append("Chưa xác định đủ số lượng và đơn giá. Hãy nhập thành tiền.") }
            }
        } else if ![.balance, .todayCollections, .overdue].contains(intent) {
            warnings.append("Cần một số tiền rõ ràng có đơn vị; nhiều khoản cần tách thành giao dịch riêng.")
        }
        if intent == .unknown { warnings.append("Chưa rõ yêu cầu. Hãy chọn loại giao dịch thủ công.") }
        return VoiceDraft(transcript: text, intent: intent, candidateIDs: candidates.map(\.id), amount: amount, effectiveDate: date, warnings: warnings)
    }
}
public enum CustomerMatcher {
    public static func match(_ text: String, customers: [Customer]) -> [Customer] {
        let key = " " + TextKey.normalize(text).replacingOccurrences(of: "?", with: " ").replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: ",", with: " ") + " "
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
