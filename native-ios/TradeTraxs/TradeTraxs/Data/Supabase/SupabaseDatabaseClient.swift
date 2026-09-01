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

    /// Exact row count via PostgREST `Prefer: count=exact` (web `{ count: "exact", head: true }`).
    func count(from table: String, query: [URLQueryItem]) async throws -> Int

    func insert<Body: Encodable, T: Decodable>(
        _ body: Body,
        into table: String,
        query: [URLQueryItem],
        returning type: T.Type
    ) async throws -> T

    /// PostgREST insert with `return=minimal` — required for conversation shell before participants exist (RLS).
    func insert<Body: Encodable>(_ body: Body, into table: String) async throws

    func update<Body: Encodable, T: Decodable>(
        _ body: Body,
        table: String,
        query: [URLQueryItem],
        returning type: T.Type
    ) async throws -> T

    /// Bulk-safe PostgREST patch — `return=minimal` (no single-row Accept header).
    func update<Body: Encodable>(
        _ body: Body,
        table: String,
        query: [URLQueryItem]
    ) async throws

    /// PostgREST upsert (`Prefer: resolution=merge-duplicates`).
    func upsert<Body: Encodable, T: Decodable>(
        _ body: Body,
        into table: String,
        onConflict: String,
        returning type: T.Type,
        select: String
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

    /// Convenience — insert with representation and no query filters (legacy call sites).
    func insert<Body: Encodable, T: Decodable>(
        _ body: Body,
        into table: String,
        returning type: T.Type
    ) async throws -> T {
        try await insert(body, into: table, query: [], returning: type)
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

    func count(from table: String, query: [URLQueryItem]) async throws -> Int {
        var items = query
        if !items.contains(where: { $0.name == "select" }) {
            items.insert(SupabaseQuery.select("id"), at: 0)
        }
        if !items.contains(where: { $0.name == "limit" }) {
            items.append(URLQueryItem(name: "limit", value: "0"))
        }
        let response = try await transport.send(
            host: .supabase,
            path: "/rest/v1/\(table)",
            method: .get,
            queryItems: items,
            headers: [
                "Prefer": "count=exact",
                "Accept": "application/json",
            ]
        )
        return Self.parseExactCount(from: response) ?? 0
    }

    private static func parseExactCount(from response: HTTPResponse) -> Int? {
        let headers = response.httpURLResponse.allHeaderFields
        let contentRange = headers.first { key, _ in
            String(describing: key).lowercased() == "content-range"
        }?.value as? String
        guard let contentRange else { return nil }
        // Forms: "0-0/123", "*/123", "0-24/123"
        guard let slash = contentRange.lastIndex(of: "/") else { return nil }
        let total = contentRange[contentRange.index(after: slash)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if total == "*" { return nil }
        return Int(total)
    }

    func insert<Body: Encodable, T: Decodable>(
        _ body: Body,
        into table: String,
        query: [URLQueryItem],
        returning type: T.Type
    ) async throws -> T {
        let data = try transport.encodeJSON(body)
        let response = try await transport.send(
            host: .supabase,
            path: "/rest/v1/\(table)",
            method: .post,
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
                throw AppError.unknown(message: "Insert returned empty representation")
            }
            return first
        }
    }

    func insert<Body: Encodable>(_ body: Body, into table: String) async throws {
        let data = try transport.encodeJSON(body)
        _ = try await transport.send(
            host: .supabase,
            path: "/rest/v1/\(table)",
            method: .post,
            headers: [
                "Prefer": "return=minimal",
                "Accept": "application/json",
            ],
            body: data
        )
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

    func update<Body: Encodable>(
        _ body: Body,
        table: String,
        query: [URLQueryItem]
    ) async throws {
        let data = try transport.encodeJSON(body)
        _ = try await transport.send(
            host: .supabase,
            path: "/rest/v1/\(table)",
            method: .patch,
            queryItems: query,
            headers: [
                "Prefer": "return=minimal",
                "Accept": "application/json",
            ],
            body: data
        )
    }

    func upsert<Body: Encodable, T: Decodable>(
        _ body: Body,
        into table: String,
        onConflict: String,
        returning type: T.Type,
        select: String
    ) async throws -> T {
        let data = try transport.encodeJSON(body)
        let response = try await transport.send(
            host: .supabase,
            path: "/rest/v1/\(table)",
            method: .post,
            queryItems: [
                URLQueryItem(name: "on_conflict", value: onConflict),
                SupabaseQuery.select(select),
            ],
            headers: [
                "Prefer": "resolution=merge-duplicates,return=representation",
                "Accept": "application/vnd.pgrst.object+json",
            ],
            body: data
        )
        do {
            return try transport.decoder.decode(type, from: response)
        } catch {
            let rows = try transport.decoder.decode([T].self, from: response)
            guard let first = rows.first else {
                throw AppError.unknown(message: "Upsert returned empty representation")
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
        let correlation = BackendV2RpcStageTracer.begin(functionName)
        BackendV2RpcStageTracer.trace(functionName, stage: "urlsession.task.started", correlation: correlation)
        let response = try await transport.send(
            host: .supabase,
            path: "/rest/v1/rpc/\(functionName)",
            method: .post,
            body: parametersJSON ?? Data("{}".utf8)
        )
        BackendV2RpcStageTracer.trace(
            functionName,
            stage: "http.response.received",
            correlation: correlation,
            detail: "status=\(response.statusCode) bytes=\(response.data.count)"
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

    func count(from table: String, query: [URLQueryItem]) async throws -> Int {
        _ = (table, query)
        throw AppError.authentication(.notConfigured)
    }

    func insert<Body: Encodable, T: Decodable>(
        _ body: Body,
        into table: String,
        query: [URLQueryItem],
        returning type: T.Type
    ) async throws -> T {
        _ = (body, table, query, type)
        throw AppError.authentication(.notConfigured)
    }

    func insert<Body: Encodable>(_ body: Body, into table: String) async throws {
        _ = (body, table)
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

    func update<Body: Encodable>(
        _ body: Body,
        table: String,
        query: [URLQueryItem]
    ) async throws {
        _ = (body, table, query)
        throw AppError.authentication(.notConfigured)
    }

    func upsert<Body: Encodable, T: Decodable>(
        _ body: Body,
        into table: String,
        onConflict: String,
        returning type: T.Type,
        select: String
    ) async throws -> T {
        _ = (body, table, onConflict, type, select)
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
