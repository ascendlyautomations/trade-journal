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

nonisolated enum ISO8601 {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let fallback: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func date(from string: String?) -> Date? {
        guard let string else { return nil }
        return formatter.date(from: string) ?? fallback.date(from: string)
    }

    static func string(from date: Date) -> String {
        formatter.string(from: date)
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
