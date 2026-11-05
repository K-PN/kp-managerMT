import Foundation

public struct MoneyParse: Equatable, Sendable {
    public var amount: Int64?
    public var alternatives: [Int64]
    public var warning: String?
    public init(amount: Int64? = nil, alternatives: [Int64] = [], warning: String? = nil) {
        self.amount = amount; self.alternatives = alternatives; self.warning = warning
    }
}

public struct MoneyMention: Sendable {
    public let text: String
    public let range: NSRange
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
            if token.range(of: #"^\d+\.\d{1,2}$"#, options: .regularExpression) != nil {
                return Decimal(string: token, locale: Locale(identifier: "en_US_POSIX"))
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
            } else if token == "muoi" || token == "chuc" {
                guard !usedTens else { return nil }; value += (pending ?? 1) * 10
                pending = nil; usedTens = true
            } else if token == "linh" || token == "le" {
                guard usedHundred && pending == nil else { return nil }
            } else { return nil }
        }
        return Decimal(value + (pending ?? 0))
    }
    /// OCR keeps requiring currency units. Financial voice commands also accept
    /// a clearly grouped or large trailing VND value after an item description.
    public func spans(in text: String, allowBareVND: Bool = false) -> [String] {
        mentions(in: text, allowBareVND: allowBareVND).map(\.text)
    }
    public func mentions(in text: String, allowBareVND: Bool = false) -> [MoneyMention] {
        // Keep an index map while folding accents, so item names retain their
        // original spelling even for decomposed Unicode or repeated spaces.
        var normalized = "", sourceRanges: [NSRange] = []
        var cursor = text.startIndex
        while cursor < text.endIndex {
            let next = text.index(after: cursor), character = text[cursor]
            let source = NSRange(cursor..<next, in: text)
            let folded = character == "₫" ? " dong " : character.isWhitespace ? " " : TextKey.normalize(String(character))
            normalized += folded
            sourceRanges.append(contentsOf: repeatElement(source, count: folded.utf16.count))
            cursor = next
        }
        let word = #"(?:\d+(?:[.,]\d+)*|khong|mot|hai|ba|bon|tu|nam|lam|sau|bay|tam|chin|tram|muoi|chuc|linh|le)"#
        let pattern = "(?<![\\p{L}\\p{N}.,/\\-])(?:\(word)\\s+)*(?:\(word))\\s*(?:ty|trieu|nghin|ngan|k|dong|vnd|d)\\b(?:\\s+(?:\(word)|ty|trieu|nghin|ngan|ruoi)\\b)*"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var found: [(NSRange, String)] = regex.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)).compactMap {
            guard let range = Range($0.range, in: normalized) else { return nil }
            var location = $0.range, value = String(normalized[range])
            // A product name can end in a number-word, e.g. “sữa ông Thọ
            // một 20 nghìn”. Prefer the explicit numeric price before its unit,
            // but never shorten ambiguous “hai triệu ba” or repeated scales.
            let parsed = parse(value)
            if parsed.amount == nil, parsed.alternatives.isEmpty,
               let unit = value.range(of: #"\b(?:ty|trieu|nghin|ngan|k|dong|vnd|d)\b"#, options: .regularExpression),
               let numeric = try? NSRegularExpression(pattern: #"\d+(?:[.,]\d+)*"#),
               let last = numeric.matches(in: value, range: NSRange(value.startIndex..<unit.lowerBound, in: value)).last,
               last.range.location > 0, let suffix = Range(NSRange(location: last.range.location, length: value.utf16.count - last.range.location), in: value) {
                let candidate = String(value[suffix])
                if parse(candidate).amount != nil {
                    location = NSRange(location: location.location + last.range.location, length: location.length - last.range.location)
                    value = candidate
                }
            }
            return (location, value)
        }
        if allowBareVND, let numbers = try? NSRegularExpression(pattern: #"(?<![\p{L}\p{N}.,/\-])(?:\d{1,3}(?:\.\d{3})+|\d+)(?![\p{L}\p{N}]|[.,]\d)"#) {
            for match in numbers.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) {
                guard !found.contains(where: { NSIntersectionRange($0.0, match.range).length > 0 }),
                      let range = Range(match.range, in: normalized) else { continue }
                let before = String(normalized[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let after = String(normalized[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                let labelled = before.range(of: #"\b(?:no|no tien hang|tra|tra tien hang|tra no tien hang|thu|tong|tong tien|tong tien hang|thanh tien|thanh toan|thanh toan tien hang|thanh toan no tien hang|so tien|gia)(?:\s+(?:la|them))?\s*[:=]?\s*$"#, options: .regularExpression) != nil
                let grouped = String(normalized[range]).contains(".")
                let largeNumber = Int64(normalized[range]).map { $0 >= 1_000 } ?? false
                let phone = before.range(of: #"\b(?:so dien thoai|dien thoai|sdt|ma so|ma hang)\s*[:=]?\s*$"#, options: .regularExpression) != nil
                let endsAmount = after.isEmpty || after.range(of: #"^[,.;!?]|^(?:da tra|con no|hom nay|hom qua|cho|cua|va|hoac)\b|^\d{1,3}(?:\.\d{3})+\b"#, options: .regularExpression) != nil
                guard !phone, (labelled || before.isEmpty || grouped || largeNumber), endsAmount else { continue }
                found.append((match.range, String(normalized[range]) + " dong"))
            }
        }
        return found.sorted { $0.0.location < $1.0.location }.compactMap { range, value in
            guard range.length > 0, range.location >= 0, NSMaxRange(range) <= sourceRanges.count else { return nil }
            let first = sourceRanges[range.location], last = sourceRanges[NSMaxRange(range) - 1]
            return MoneyMention(text: value, range: NSRange(location: first.location, length: NSMaxRange(last) - first.location))
        }
    }
}
