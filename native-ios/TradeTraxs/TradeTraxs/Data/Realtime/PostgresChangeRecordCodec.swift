import Foundation

/// JSON encode/decode for postgres_changes `record` payloads on Realtime signals.
nonisolated enum PostgresChangeRecordCodec {
    static func encode(_ record: [String: Any]) -> Data? {
        guard JSONSerialization.isValidJSONObject(record) else { return nil }
        return try? JSONSerialization.data(withJSONObject: record, options: [])
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }

    static func dictionary(from data: Data) -> [String: Any]? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any]
        else { return nil }
        return dict
    }
}
