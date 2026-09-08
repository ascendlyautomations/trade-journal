import Foundation

/// USD currency editing + display helpers for Record Payout money fields.
enum CurrencyAmountFieldSupport {
    /// Strips grouping/currency symbols and clamps to a valid currency fraction (max 2 decimal places).
    static func sanitizeInput(_ raw: String) -> String {
        let stripped = raw
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var digitsAndDot = ""
        var sawDot = false
        for character in stripped {
            if character.isWholeNumber {
                digitsAndDot.append(character)
            } else if character == ".", !sawDot {
                sawDot = true
                digitsAndDot.append(character)
            }
        }

        guard let dotIndex = digitsAndDot.firstIndex(of: ".") else {
            return digitsAndDot
        }

        let whole = String(digitsAndDot[..<dotIndex])
        let fractionStart = digitsAndDot.index(after: dotIndex)
        let fraction = String(digitsAndDot[fractionStart...].prefix(2))
        if fraction.isEmpty, digitsAndDot.hasSuffix(".") {
            return whole + "."
        }
        return whole + "." + fraction
    }

    static func parse(_ raw: String) -> Decimal? {
        let sanitized = sanitizeInput(raw)
        guard !sanitized.isEmpty, sanitized != "." else { return nil }
        guard let value = Decimal(string: sanitized), value >= 0 else { return nil }
        return value
    }

    /// Standard USD display — always 2 decimal places, e.g. `$53,242.50`.
    static func formatDisplay(_ amount: Decimal) -> String {
        usdDisplayFormatter.string(from: NSDecimalNumber(decimal: amount)) ?? "$0.00"
    }

    /// Programmatic seed for editable text — preserves cents without grouping, e.g. `51242.50`.
    static func seedEditingText(from amount: Decimal) -> String {
        var value = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .plain)
        return usdEditingSeedFormatter.string(from: NSDecimalNumber(decimal: rounded)) ?? "0.00"
    }

    private static let usdDisplayFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let usdEditingSeedFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}
