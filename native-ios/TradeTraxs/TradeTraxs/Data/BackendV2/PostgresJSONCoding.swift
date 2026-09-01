import Foundation

/// Decodes Postgres/PostgREST JSON numbers that may arrive as Int, Double, or numeric String.
nonisolated struct PostgresFlexibleDouble: Codable, Sendable, Equatable {
    var value: Double?

    init(_ value: Double?) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
            return
        }
        if let double = try? container.decode(Double.self) {
            value = double
            return
        }
        if let int = try? container.decode(Int.self) {
            value = Double(int)
            return
        }
        if let string = try? container.decode(String.self) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                value = nil
                return
            }
            if let parsed = Double(trimmed) {
                value = parsed
                return
            }
            if let decimal = Decimal(string: trimmed) {
                value = NSDecimalNumber(decimal: decimal).doubleValue
                return
            }
        }
        throw DecodingError.typeMismatch(
            Double.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected Postgres numeric JSON (number or numeric string)"
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value {
            try container.encode(value)
        } else {
            try container.encodeNil()
        }
    }

    var decimal: Decimal? {
        value.map { Decimal($0) }
    }
}

/// Decodes Postgres booleans that may arrive as `true`/`false` or `0`/`1`.
nonisolated struct PostgresFlexibleBool: Codable, Sendable, Equatable {
    var value: Bool?

    init(_ value: Bool?) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
            return
        }
        if let bool = try? container.decode(Bool.self) {
            value = bool
            return
        }
        if let int = try? container.decode(Int.self) {
            value = int != 0
            return
        }
        throw DecodingError.typeMismatch(
            Bool.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected boolean or 0/1 integer"
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value {
            try container.encode(value)
        } else {
            try container.encodeNil()
        }
    }
}

/// Account size is stored as `text` in Postgres — wire JSON is usually a string.
nonisolated struct PostgresAccountSizeWire: Codable, Sendable, Equatable {
    var raw: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            raw = nil
            return
        }
        if let string = try? container.decode(String.self) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            raw = trimmed.isEmpty ? nil : trimmed
            return
        }
        if let double = try? container.decode(Double.self) {
            raw = Self.string(from: double)
            return
        }
        if let int = try? container.decode(Int.self) {
            raw = String(int)
            return
        }
        throw DecodingError.typeMismatch(
            String.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected account_size string or numeric JSON"
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let raw {
            try container.encode(raw)
        } else {
            try container.encodeNil()
        }
    }

    var decimal: Decimal? {
        guard let raw else { return nil }
        return Decimal(string: raw) ?? Double(raw).map { Decimal($0) }
    }

    private static func string(from double: Double) -> String {
        if double.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(double))
        }
        return String(double)
    }
}

/// Postgres `bigint` / numeric counts may arrive as Int, Double, or numeric String.
nonisolated struct PostgresFlexibleInt: Codable, Sendable, Equatable {
    var value: Int

    init(_ value: Int) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = 0
            return
        }
        if let intValue = try? container.decode(Int.self) {
            value = intValue
            return
        }
        if let doubleValue = try? container.decode(Double.self) {
            value = Int(doubleValue.rounded(.towardZero))
            return
        }
        if let stringValue = try? container.decode(String.self),
           let parsed = Int(stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            value = parsed
            return
        }
        throw DecodingError.typeMismatch(
            Int.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected Postgres count JSON (number or numeric string)"
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
