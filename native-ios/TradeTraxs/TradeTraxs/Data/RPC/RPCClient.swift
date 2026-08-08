import Foundation

/// Postgres RPC / remote procedure surface.
nonisolated protocol RPCClient: Sendable {
    func call(functionName: String, parameters: [String: String]) async throws -> Data
    func call(functionName: String, jsonBody: Data) async throws -> Data
}

nonisolated struct DefaultRPCClient: RPCClient {
    private let provider: any SupabaseRPCProviding
    private let database: any SupabaseDatabaseExecuting

    init(
        provider: any SupabaseRPCProviding,
        database: any SupabaseDatabaseExecuting
    ) {
        self.provider = provider
        self.database = database
    }

    func call(functionName: String, parameters: [String: String]) async throws -> Data {
        try await provider.invoke(functionName: functionName, parameters: parameters)
    }

    func call(functionName: String, jsonBody: Data) async throws -> Data {
        try await database.rpcData(functionName: functionName, parametersJSON: jsonBody)
    }
}
