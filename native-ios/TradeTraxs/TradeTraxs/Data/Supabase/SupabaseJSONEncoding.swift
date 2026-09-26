import Foundation

/// PostgREST-safe JSON encoding — never passes invalid top-level values to ``JSONSerialization``.
nonisolated enum SupabaseJSONEncoding {
    enum Error: Swift.Error, Sendable, Equatable {
        case invalidTopLevelType(String)
        case invalidJSONObjectGraph
        case encodeFailed
    }

    static func encode<T: Encodable>(_ value: T, dateEncoding: JSONEncoder.DateEncodingStrategy = .iso8601) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = dateEncoding
        do {
            let data = try encoder.encode(value)
            try assertPostgRESTBody(data)
            return data
        } catch let error as Error {
            throw error
        } catch {
            throw Error.encodeFailed
        }
    }

    /// Validates JSON bytes are a PostgREST object or array (never a bare string/number/bool).
    static func assertPostgRESTBody(_ data: Data) throws {
        guard !data.isEmpty else { return }
        let top: Any
        do {
            top = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw Error.invalidTopLevelType("unparseable")
        }

        if top is String || top is NSString {
            throw Error.invalidTopLevelType("String")
        }
        if top is NSNumber {
            throw Error.invalidTopLevelType("Number")
        }
        if top is Bool {
            throw Error.invalidTopLevelType("Bool")
        }
        if top is [String: Any] || top is NSDictionary || top is NSArray {
            return
        }
        if let rows = top as? [Any], rows.allSatisfy({ $0 is [String: Any] || $0 is NSDictionary }) {
            return
        }
        throw Error.invalidTopLevelType(String(describing: type(of: top)))
    }

    /// Safe ``JSONSerialization`` wrapper for untyped RPC argument dictionaries.
    static func data(fromJSONObject object: Any) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw Error.invalidJSONObjectGraph
        }
        return try JSONSerialization.data(withJSONObject: object, options: [])
    }
}
