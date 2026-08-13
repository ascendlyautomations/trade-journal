import Foundation

/// Bidirectional DTO ↔ Domain mapping contract.
nonisolated protocol DTOMapper {
    associatedtype DTO
    associatedtype DomainModel
    static func mapToDomain(_ dto: DTO) throws -> DomainModel
    static func mapToDTO(_ domain: DomainModel) throws -> DTO
}

nonisolated enum MappingError: Error, Sendable, Equatable {
    case missingField(String)
    case invalidValue(field: String, value: String)
}

/// Parses timestamps returned by production Supabase / PostgREST the same ways
/// the web app tolerates via `new Date(...)`.
nonisolated enum ISO8601 {
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let posix: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let postgresPatterns = [
        "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX",
        "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
        "yyyy-MM-dd'T'HH:mm:ssXXXXX",
        "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ",
        "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ",
        "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
        "yyyy-MM-dd HH:mm:ss.SSSSSSXXXXX",
        "yyyy-MM-dd HH:mm:ss.SSSXXXXX",
        "yyyy-MM-dd HH:mm:ssXXXXX",
        "yyyy-MM-dd HH:mm:ss.SSSSSSZZZZZ",
        "yyyy-MM-dd HH:mm:ss.SSSZZZZZ",
        "yyyy-MM-dd HH:mm:ssZZZZZ",
        "yyyy-MM-dd HH:mm:ss.SSSSSSX",
        "yyyy-MM-dd HH:mm:ss.SSSX",
        "yyyy-MM-dd HH:mm:ssX",
        "yyyy-MM-dd HH:mm:ss.SSSSSSZ",
        "yyyy-MM-dd HH:mm:ss.SSSZ",
        "yyyy-MM-dd HH:mm:ssZ",
        "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
        "yyyy-MM-dd'T'HH:mm:ss.SSS",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd HH:mm:ss.SSSSSS",
        "yyyy-MM-dd HH:mm:ss.SSS",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd",
    ]

    static func date(from string: String?) -> Date? {
        guard let raw = string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }

        // Postgres often emits 1–9 fractional digits; ISO8601DateFormatter is picky.
        // Normalize early so Stories/feed timestamps match web `new Date(...)`.
        let candidates = timestampCandidates(from: raw)
        for candidate in candidates {
            if let date = fractional.date(from: candidate) ?? standard.date(from: candidate) {
                return date
            }
            if let date = try? Date(candidate, strategy: .iso8601) {
                return date
            }
        }

        for candidate in candidates {
            for pattern in postgresPatterns {
                posix.dateFormat = pattern
                if let date = posix.date(from: candidate) {
                    return date
                }
            }
        }

        // Date-only prefix fallback (trade_date / legacy `date`).
        if raw.count >= 10 {
            posix.dateFormat = "yyyy-MM-dd"
            if let date = posix.date(from: String(raw.prefix(10))) {
                return date
            }
        }

        return nil
    }

    /// Variants that cover space/`T`, timezone colon expansion, and fractional-second width.
    private static func timestampCandidates(from raw: String) -> [String] {
        var values: [String] = []
        func append(_ value: String) {
            if !values.contains(value) { values.append(value) }
        }

        append(raw)
        if raw.contains(" "), let idx = raw.firstIndex(of: " ") {
            var withT = raw
            withT.replaceSubrange(idx...idx, with: "T")
            append(withT)
        }

        for base in Array(values) {
            append(expandTimezoneColon(base))
            append(normalizeFractionalSeconds(base, digits: 6))
            append(normalizeFractionalSeconds(base, digits: 3))
            append(expandTimezoneColon(normalizeFractionalSeconds(base, digits: 6)))
            append(expandTimezoneColon(normalizeFractionalSeconds(base, digits: 3)))
        }
        return values
    }

    /// Pads/truncates `.S+` fractional seconds to a fixed width before the timezone/Z/end.
    private static func normalizeFractionalSeconds(_ value: String, digits: Int) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(\.\d+)(?=(?:Z|[+-]\d{2}(?::?\d{2})?)$|$)"#,
            options: []
        ) else {
            return value
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, options: [], range: range),
              let fracRange = Range(match.range(at: 1), in: value) else {
            return value
        }
        var fraction = String(value[fracRange].dropFirst()) // drop '.'
        if fraction.count == digits { return value }
        if fraction.count > digits {
            fraction = String(fraction.prefix(digits))
        } else {
            fraction = fraction.padding(toLength: digits, withPad: "0", startingAt: 0)
        }
        return value.replacingCharacters(in: fracRange, with: ".\(fraction)")
    }

    static func string(from date: Date) -> String {
        fractional.string(from: date)
    }

    /// Turns trailing `+00` / `-05` into `+00:00` / `-05:00` when minutes are absent.
    private static func expandTimezoneColon(_ value: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"([+-]\d{2})(?!:?\d{2})$"#,
            options: []
        ) else {
            return value
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, options: [], range: range),
              let tzRange = Range(match.range(at: 1), in: value) else {
            return value
        }
        return value.replacingCharacters(in: tzRange, with: "\(value[tzRange]):00")
    }
}

nonisolated enum DecimalParser {
    static func parse(_ string: String?) -> Decimal? {
        guard let string, let value = Decimal(string: string) else { return nil }
        return value
    }

    static func parse(_ number: Double?) -> Decimal? {
        guard let number else { return nil }
        return Decimal(number)
    }

    static func parseFlexible(_ value: FlexibleNumber?) -> Decimal? {
        value?.decimal
    }

    static func string(from decimal: Decimal?) -> String? {
        guard let decimal else { return nil }
        return NSDecimalNumber(decimal: decimal).stringValue
    }
}

/// Decodes JSON numbers or numeric strings into ``Decimal``.
nonisolated struct FlexibleNumber: Codable, Sendable, Equatable {
    var decimal: Decimal?

    init(_ decimal: Decimal?) {
        self.decimal = decimal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            decimal = nil
        } else if let value = try? container.decode(Decimal.self) {
            decimal = value
        } else if let value = try? container.decode(Double.self) {
            decimal = Decimal(value)
        } else if let value = try? container.decode(Int.self) {
            decimal = Decimal(value)
        } else if let value = try? container.decode(String.self) {
            decimal = Decimal(string: value)
        } else {
            decimal = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let decimal {
            try container.encode(NSDecimalNumber(decimal: decimal).doubleValue)
        } else {
            try container.encodeNil()
        }
    }
}
