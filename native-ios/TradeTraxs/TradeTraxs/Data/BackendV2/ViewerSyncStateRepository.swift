import Foundation

nonisolated struct ViewerSyncStateRepository: Sendable {
    private let client: BackendV2RPCClient

    init(rpc: any RPCClient) {
        self.client = BackendV2RPCClient(transport: rpc)
    }

    func loadSyncState() async throws -> ViewerSyncStateV1 {
        let value = try await client.call(
            .viewerSyncState,
            as: ViewerSyncStateV1.self,
            options: BackendV2RPCCallOptions(flagName: "backendV2.syncState")
        )
        try value.validateContractVersion()
        return value
    }
}
