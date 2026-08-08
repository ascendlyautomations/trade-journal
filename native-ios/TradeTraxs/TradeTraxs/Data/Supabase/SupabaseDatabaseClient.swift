import Foundation

/// PostgREST table / RPC gateway used by Default repositories.
nonisolated protocol SupabaseDatabaseExecuting: Sendable {
    var isConfigured: Bool { get }

    func select<T: Decodable>(
        _ type: T.Type,
        from table: String,
        query: [URLQueryItem],
        headers: [String: String]
    ) async throws -> [T]

    func selectOne<T: Decodable>(
        _ type: T.Type,
        from table: String,
        query: [URLQueryItem]
    ) async throws -> T

    func insert<Body: Encodable, T: Decodable>(
        _ body: Body,
        into table: String,
        returning type: T.Type
    ) async throws -> T

    func update<Body: Encodable, T: Decodable>(
        _ body: Body,
        table: String,
        query: [URLQueryItem],
        returning type: T.Type
    ) async throws -> T

    func delete(from table: String, query: [URLQueryItem]) async throws

    func rpcData(functionName: String, parametersJSON: Data?) async throws -> Data
}

extension SupabaseDatabaseExecuting {
    func select<T: Decodable>(
        _ type: T.Type,
        from table: String,
        query: [URLQueryItem] = []
    ) async throws -> [T] {
        try await select(type, from: table, query: query, headers: [:])
    }
}

nonisolated struct SupabaseDatabaseClient: SupabaseDatabaseExecuting {
    private let transport: SupabaseTransport

    init(transport: SupabaseTransport) {
        self.transport = transport
    }

    var isConfigured: Bool { transport.isConfigured }

    func select<T: Decodable>(
        _ type: T.Type,
        from table: String,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:]
    ) async throws -> [T] {
        var merged = headers
        if merged["Accept"] == nil {
            merged["Accept"] = "application/json"
        }
        return try await transport.sendDecodable(
            [T].self,
            host: .supabase,
            path: "/rest/v1/\(table)",
            method: .get,
            queryItems: query,
            headers: merged
        )
    }

    func selectOne<T: Decodable>(
        _ type: T.Type,
        from table: String,
        query: [URLQueryItem]
    ) async throws -> T {
        let response = try await transport.send(
            host: .supabase,
            path: "/rest/v1/\(table)",
            method: .get,
            queryItems: query,
            headers: [
                "Accept": "application/vnd.pgrst.object+json",
            ]
        )
        do {
            return try transport.decoder.decode(type, from: response)
        } catch {
            throw AppError.domain(.notFound(entity: table, id: "selectOne"))
        }
    }

    func insert<Body: Encodable, T: Decodable>(
        _ body: Body,
        into table: String,
        returning type: T.Type
    ) async throws -> T {
        let data = try transport.encodeJSON(body)
        let response = try await transport.send(
            host: .supabase,
            path: "/rest/v1/\(table)",
            method: .post,
            headers: [
                "Prefer": "return=representation",
                "Accept": "application/vnd.pgrst.object+json",
            ],
            body: data
        )
        do {
            return try transport.decoder.decode(type, from: response)
        } catch {
            let rows = try transport.decoder.decode([T].self, from: response)
            guard let first = rows.first else {
                throw AppError.unknown(message: "Insert returned empty representation")
            }
            return first
        }
    }

    func update<Body: Encodable, T: Decodable>(
        _ body: Body,
        table: String,
        query: [URLQueryItem],
        returning type: T.Type
    ) async throws -> T {
        let data = try transport.encodeJSON(body)
        let response = try await transport.send(
            host: .supabase,
            path: "/rest/v1/\(table)",
            method: .patch,
            queryItems: query,
            headers: [
                "Prefer": "return=representation",
                "Accept": "application/vnd.pgrst.object+json",
            ],
            body: data
        )
        do {
            return try transport.decoder.decode(type, from: response)
        } catch {
            let rows = try transport.decoder.decode([T].self, from: response)
            guard let first = rows.first else {
                throw AppError.domain(.notFound(entity: table, id: "update"))
            }
            return first
        }
    }

    func delete(from table: String, query: [URLQueryItem]) async throws {
        _ = try await transport.send(
            host: .supabase,
            path: "/rest/v1/\(table)",
            method: .delete,
            queryItems: query,
            headers: ["Prefer": "return=minimal"]
        )
    }

    func rpcData(functionName: String, parametersJSON: Data?) async throws -> Data {
        let response = try await transport.send(
            host: .supabase,
            path: "/rest/v1/rpc/\(functionName)",
            method: .post,
            body: parametersJSON ?? Data("{}".utf8)
        )
        return response.data
    }
}

/// Test / unconfigured double.
nonisolated struct UnconfiguredSupabaseDatabaseClient: SupabaseDatabaseExecuting {
    var isConfigured: Bool { false }

    func select<T: Decodable>(
        _ type: T.Type,
        from table: String,
        query: [URLQueryItem],
        headers: [String: String]
    ) async throws -> [T] {
        _ = (type, table, query, headers)
        throw AppError.authentication(.notConfigured)
    }

    func selectOne<T: Decodable>(
        _ type: T.Type,
        from table: String,
        query: [URLQueryItem]
    ) async throws -> T {
        _ = (type, table, query)
        throw AppError.authentication(.notConfigured)
    }

    func insert<Body: Encodable, T: Decodable>(
        _ body: Body,
        into table: String,
        returning type: T.Type
    ) async throws -> T {
        _ = (body, table, type)
        throw AppError.authentication(.notConfigured)
    }

    func update<Body: Encodable, T: Decodable>(
        _ body: Body,
        table: String,
        query: [URLQueryItem],
        returning type: T.Type
    ) async throws -> T {
        _ = (body, table, query, type)
        throw AppError.authentication(.notConfigured)
    }

    func delete(from table: String, query: [URLQueryItem]) async throws {
        _ = (table, query)
        throw AppError.authentication(.notConfigured)
    }

    func rpcData(functionName: String, parametersJSON: Data?) async throws -> Data {
        _ = (functionName, parametersJSON)
        throw AppError.authentication(.notConfigured)
    }
}
