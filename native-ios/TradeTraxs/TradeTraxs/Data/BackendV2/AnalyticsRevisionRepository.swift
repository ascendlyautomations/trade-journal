import Foundation

nonisolated struct AnalyticsRevisionRepository: Sendable {
    private let client: BackendV2RPCClient

    init(rpc: any RPCClient) {
        self.client = BackendV2RPCClient(transport: rpc)
    }

    func loadRevision() async throws -> AnalyticsRevisionV1 {
        try await client.call(
            .analyticsRevision,
            as: AnalyticsRevisionV1.self,
            options: BackendV2RPCCallOptions(flagName: "backendV2.analyticsRevisionRepair")
        )
    }
}
