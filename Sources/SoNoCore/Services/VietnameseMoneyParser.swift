import Foundation

public struct MoneyParse: Equatable, Sendable {
    public var amount: Int64?
    public var alternatives: [Int64]
    public var warning: String?
    public init(amount: Int64? = nil, alternatives: [Int64] = [], warning: String? = nil) {
        self.amount = amount; self.alternatives = alternatives; self.warning = warning
    }
}

public struct VietnameseMoneyParser: Sendable {
    private static let digits: [String: Int64] = ["khong": 0, "mot": 1, "hai": 2, "ba": 3, "bon": 4, "tu": 4, "nam": 5, "lam": 5, "sau": 6, "bay": 7, "tam": 8, "chin": 9]
    private static let scales: [String: Int64] = ["ty": 1_000_000_000, "trieu": 1_000_000, "nghin": 1_000, "ngan": 1_000, "k": 1_000]
    public init() {}
    public func parse(_ input: String) -> MoneyParse {
        guard input.count <= 200 else { return MoneyParse(warning: "Số tiền quá dài.") }
        let normalized = TextKey.normalize(input.replacingOccurrences(of: "₫", with: " dong "))
            .replacingOccurrences(of: #"(?<=\d)(?=(?:ty|trieu|nghin|ngan|k|dong|vnd)\b)"#, with: " ", options: .regularExpression)
        var tokens = normalized
            .split(separator: " ").map(String.init)
        if tokens.last == "dong" || tokens.last == "vnd" || tokens.last == "d" { tokens.removeLast() }
        guard !tokens.isEmpty, !tokens.contains(where: { $0.contains("-") }) else { return MoneyParse(warning: "Số tiền phải dương và đầy đủ.") }
        do {
            var total: Int64 = 0, group: [String] = [], lastScale: Int64?, previousScale = Int64.max
            for token in tokens {
                if let scale = Self.scales[token] {
                    guard scale < previousScale, !group.isEmpty, let value = number(group) else { return MoneyParse(warning: "Không đọc được số tiền.") }
                    total = try CheckedMoney.add(total, scaled(value, by: scale))
                    previousScale = scale; lastScale = scale; group = []
                } else { group.append(token) }
            }
            if group == ["ruoi"], let scale = lastScale {
                total = try CheckedMoney.add(total, scale / 2)
            } else if !group.isEmpty {
                guard let tail = number(group) else { return MoneyParse(warning: "Số tiền còn thiếu hoặc không rõ.") }
                if let scale = lastScale, scale >= 1_000_000, tail > 0, !group.contains("tram") {
                    let alternativeScale = tail < 10 ? scale / 10 : scale / 1_000
                    return MoneyParse(alternatives: [try CheckedMoney.add(total, scaled(tail, by: 1)), try CheckedMoney.add(total, scaled(tail, by: alternativeScale))], warning: "Cách nói rút gọn có nhiều nghĩa. Hãy nhập lại số tiền bằng đồng.")
                }
                let impliedScale: Int64 = (lastScale ?? 0) >= 1_000_000 && group.contains("tram") ? (lastScale! / 1_000) : 1
                total = try CheckedMoney.add(total, scaled(tail, by: impliedScale))
            }
            guard total > 0 else { return MoneyParse(warning: "Số tiền phải lớn hơn 0.") }
            return MoneyParse(amount: total)
        } catch { return MoneyParse(warning: "Số tiền vượt giới hạn hoặc không tròn đồng.") }
    }
    private func scaled(_ value: Decimal, by scale: Int64) throws -> Int64 {
        let decimal = value * Decimal(scale)
        guard decimal > 0, decimal <= Decimal(Int64.max) else { throw LedgerError.overflow }
        let number = NSDecimalNumber(decimal: decimal)
        let integer = number.int64Value
        guard Decimal(integer) == decimal else { throw LedgerError.invalid("Tiền phải tròn đồng.") }
        return integer
    }
    private func number(_ tokens: [String]) -> Decimal? {
        if tokens.count == 1 {
            if let digit = Self.digits[tokens[0]] { return Decimal(digit) }
            let token = tokens[0]
            if token.range(of: #"^\d{1,3}(\.\d{3})+$"#, options: .regularExpression) != nil {
                return Decimal(string: token.replacingOccurrences(of: ".", with: ""), locale: Locale(identifier: "en_US_POSIX"))
            }
            if token.range(of: #"^\d+(,\d+)?$"#, options: .regularExpression) != nil {
                return Decimal(string: token.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX"))
            }
            return nil
        }
        var value: Int64 = 0, pending: Int64?, usedHundred = false, usedTens = false
        for token in tokens {
            if let digit = Self.digits[token] ?? Int64(token), digit >= 0 && digit <= 9 {
                guard pending == nil else { return nil }; pending = digit
            } else if token == "tram" {
                guard !usedHundred, !usedTens, let digit = pending else { return nil }
                value += digit * 100; pending = nil; usedHundred = true
            } else if token == "muoi" {
                guard !usedTens else { return nil }; value += (pending ?? 1) * 10
                pending = nil; usedTens = true
            } else if token == "linh" || token == "le" {
                guard usedHundred && pending == nil else { return nil }
            } else { return nil }
        }
        return Decimal(value + (pending ?? 0))
    }
    /// Only monetary spans with a currency unit; bare item quantities are never money.
    public func spans(in text: String) -> [String] {
        let normalized = TextKey.normalize(text)
        let word = #"(?:\d+(?:[.,]\d+)*|khong|mot|hai|ba|bon|tu|nam|lam|sau|bay|tam|chin|tram|muoi|linh|le)"#
        let pattern = "\\b(?:\(word)\\s+)*(?:\(word))\\s*(?:ty|trieu|nghin|ngan|k|dong|vnd)\\b(?:\\s+(?:\(word)|ty|trieu|nghin|ngan|ruoi)\\b)*"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)).compactMap {
            Range($0.range, in: normalized).map { String(normalized[$0]) }
        }
    }
}
