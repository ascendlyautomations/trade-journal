import Foundation

/// Web `parseCsvNumeric` — currency, commas, accounting negatives.
nonisolated enum CSVNumericParser {
    static func parse(_ raw: String?) -> Decimal? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
            return nil
        }
        if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
            s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if s.isEmpty || s == "-" || s == "—" { return nil }

        var neg = false
        if s.range(of: #"^\(.*\)$"#, options: .regularExpression) != nil
            || s.range(of: #"^\$\(.*\)$"#, options: .regularExpression) != nil
        {
            neg.toggle()
        }
        s = s.replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty || s == "$" { return nil }
        if s.hasPrefix("$"), s.count > 1 { s.removeFirst() }

        s = s.replacingOccurrences(of: "\u{2212}", with: "-")
        s = s.replacingOccurrences(of: "$", with: "")
        s = s.replacingOccurrences(of: ",", with: "")
        s = s.replacingOccurrences(of: "%", with: "")
        s = s.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)

        while s.hasPrefix("-") {
            neg.toggle()
            s.removeFirst()
        }
        if s.hasPrefix("+") { s.removeFirst() }
        if s.isEmpty || s == "." { return nil }

        guard let value = Decimal(string: s) else { return nil }
        let magnitude = abs(value)
        return neg ? -magnitude : magnitude
    }

    static func parseDouble(_ raw: String?) -> Double? {
        guard let decimal = parse(raw) else { return nil }
        return NSDecimalNumber(decimal: decimal).doubleValue
    }
}
