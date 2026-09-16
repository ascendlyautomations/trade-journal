import Foundation

/// Live thousands-separator formatting and parsing for editable numeric fields.
///
/// Display strings may contain grouping commas; parsed values and API payloads must not.
nonisolated enum NumericInputStyle: Equatable, Sendable {
    case signedInteger
    case unsignedInteger
    /// `maxFractionDigits == nil` preserves all typed fractional digits.
    case signedDecimal(maxFractionDigits: Int?)
    case unsignedDecimal(maxFractionDigits: Int?)

    var allowsSign: Bool {
        switch self {
        case .signedInteger, .signedDecimal: true
        case .unsignedInteger, .unsignedDecimal: false
        }
    }

    var allowsDecimal: Bool {
        switch self {
        case .signedInteger, .unsignedInteger: false
        case .signedDecimal, .unsignedDecimal: true
        }
    }

    var maxFractionDigits: Int? {
        switch self {
        case .signedInteger, .unsignedInteger: nil
        case .signedDecimal(let max), .unsignedDecimal(let max): max
        }
    }
}

nonisolated extension NumericInputStyle {
    static let signedPnL = NumericInputStyle.signedDecimal(maxFractionDigits: nil)
    static let unsignedCurrency = NumericInputStyle.unsignedDecimal(maxFractionDigits: 2)
    static let tradePrice = NumericInputStyle.unsignedDecimal(maxFractionDigits: nil)
    static let tradeQuantity = NumericInputStyle.unsignedDecimal(maxFractionDigits: nil)
    static let riskReward = NumericInputStyle.unsignedDecimal(maxFractionDigits: nil)
    static let accountSize = NumericInputStyle.unsignedInteger
    static let winningDays = NumericInputStyle.unsignedInteger
    static let propFirmAmount = NumericInputStyle.unsignedDecimal(maxFractionDigits: nil)
}

nonisolated enum NumericInputFieldSupport {
    /// Formats user input for display while editing (commas, sign, fraction rules).
    static func formatWhileEditing(_ raw: String, style: NumericInputStyle) -> String {
        applyGrouping(to: sanitizeForEditing(raw, style: style))
    }

    static func parse(_ display: String, style: NumericInputStyle) -> Decimal? {
        let sanitized = sanitizeForEditing(display, style: style)
        guard !sanitized.isEmpty else { return nil }
        if sanitized == "-" || sanitized == "." || sanitized == "-." { return nil }
        return Decimal(string: sanitized)
    }

    static func parseInt(_ display: String, style: NumericInputStyle) -> Int? {
        guard style.allowsDecimal == false else { return nil }
        guard let decimal = parse(display, style: style) else { return nil }
        return NSDecimalNumber(decimal: decimal).intValue
    }

    /// Plain numeric string for storage/API (no commas or currency symbols).
    static func plainNumericString(from display: String) -> String {
        display
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func seedEditingText(from value: Decimal, style: NumericInputStyle) -> String {
        let raw = NSDecimalNumber(decimal: value).stringValue
        return formatWhileEditing(raw, style: style)
    }

    static func seedEditingText(from value: Int, style: NumericInputStyle) -> String {
        formatWhileEditing(String(value), style: style)
    }

    /// Flips leading sign for signed styles (decimal pad has no minus key).
    static func toggleSignOnDisplay(_ display: String, style: NumericInputStyle) -> String {
        guard style.allowsSign else { return display }
        let trimmed = display.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return formatWhileEditing("-", style: style)
        }
        if trimmed == "-" {
            return ""
        }
        if trimmed.hasPrefix("-") {
            let magnitude = plainNumericString(from: trimmed).replacingOccurrences(of: "-", with: "")
            guard !magnitude.isEmpty else { return "" }
            return formatWhileEditing(magnitude, style: style)
        }
        let magnitude = plainNumericString(from: trimmed)
        guard !magnitude.isEmpty else { return formatWhileEditing("-", style: style) }
        return formatWhileEditing("-" + magnitude, style: style)
    }

    // MARK: - Private

    private static func sanitizeForEditing(_ raw: String, style: NumericInputStyle) -> String {
        var work = raw
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")

        var sign = ""
        if style.allowsSign {
            let trimmed = work.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "-" { return "-" }
            if trimmed.hasPrefix("-") {
                sign = "-"
                work = String(trimmed.dropFirst())
            } else if trimmed.hasPrefix("+") {
                work = String(trimmed.dropFirst())
            } else {
                work = trimmed
            }
        } else {
            work = work
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: "+", with: "")
        }

        if work.isEmpty { return sign }

        var body = ""
        var sawDot = false
        for character in work {
            if character.isWholeNumber {
                body.append(character)
            } else if style.allowsDecimal, character == ".", !sawDot {
                sawDot = true
                body.append(character)
            }
        }

        if let maxFractionDigits = style.maxFractionDigits, let dotIndex = body.firstIndex(of: ".") {
            let whole = String(body[..<dotIndex])
            let fractionStart = body.index(after: dotIndex)
            let fraction = String(body[fractionStart...].prefix(maxFractionDigits))
            if fraction.isEmpty, body.hasSuffix(".") {
                body = whole + "."
            } else {
                body = whole + "." + fraction
            }
        }

        return sign + body
    }

    private static func applyGrouping(to sanitized: String) -> String {
        if sanitized.isEmpty || sanitized == "-" { return sanitized }

        let negative = sanitized.hasPrefix("-")
        let body = negative ? String(sanitized.dropFirst()) : sanitized
        if body.isEmpty { return negative ? "-" : "" }

        let dotIndex = body.firstIndex(of: ".")
        let wholeDigits: String
        let fractionSuffix: String
        if let dotIndex {
            wholeDigits = String(body[..<dotIndex])
            fractionSuffix = String(body[dotIndex...])
        } else {
            wholeDigits = body
            fractionSuffix = ""
        }

        let groupedWhole = groupWholeDigits(wholeDigits)
        return (negative ? "-" : "") + groupedWhole + fractionSuffix
    }

    private static func groupWholeDigits(_ digits: String) -> String {
        guard !digits.isEmpty else { return "" }
        var normalized = digits
        while normalized.count > 1, normalized.hasPrefix("0") {
            normalized.removeFirst()
        }

        var grouped = ""
        var run = 0
        for character in normalized.reversed() {
            if run == 3 {
                grouped.insert(",", at: grouped.startIndex)
                run = 0
            }
            grouped.insert(character, at: grouped.startIndex)
            run += 1
        }
        return grouped
    }
}
