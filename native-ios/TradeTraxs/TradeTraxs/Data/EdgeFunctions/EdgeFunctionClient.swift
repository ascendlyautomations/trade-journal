import Foundation

/// Edge Function invocation surface (AI analyst, notifications, premium workflows).
nonisolated protocol EdgeFunctionClient: Sendable {
    func call(name: String, body: Data?) async throws -> Data
}

nonisolated enum EdgeFunctionName: String, Sendable {
    case aiTradeAnalyst = "ai-trade-analyst"
    case notifications = "notifications"
}

nonisolated struct DefaultEdgeFunctionClient: EdgeFunctionClient {
    private let provider: any SupabaseEdgeFunctionProviding

    init(provider: any SupabaseEdgeFunctionProviding) {
        self.provider = provider
    }

    func call(name: String, body: Data?) async throws -> Data {
        try await provider.invoke(name: name, body: body)
    }
}
