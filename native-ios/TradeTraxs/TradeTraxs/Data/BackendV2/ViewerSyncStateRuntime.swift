import Foundation

/// CompositionRoot-bound RPC access for post-mutation fingerprint refresh.
@MainActor
enum ViewerSyncStateRuntime {
    private static var rpc: (any RPCClient)?
    private static var profiles: (any ProfileRepository)?

    static func configure(rpc: any RPCClient, profiles: any ProfileRepository) {
        self.rpc = rpc
        self.profiles = profiles
    }

    static func resolvedProfiles(fallback: (any ProfileRepository)?) -> (any ProfileRepository)? {
        fallback ?? profiles
    }

    static func reset() {
        rpc = nil
        profiles = nil
    }

    static func noteLocalMutation(viewerID: ProfileID) {
        guard BackendV2FeatureFlags.isEnabled(.viewerSyncState), let rpc else { return }
        Task {
            await ViewerSyncStateCapturer.refreshFromServer(viewerID: viewerID.rawValue, rpc: rpc)
        }
    }
}

enum ViewerSyncStateCapturer {
    @MainActor
    static func refreshFromServer(viewerID: String, rpc: any RPCClient) async {
        guard BackendV2FeatureFlags.isEnabled(.viewerSyncState) else { return }
        let rpcName = BackendV2Versioning.RPCName.viewerSyncState.rawValue
        if await BackendV2RpcAvailability.shared.isUnavailable(rpcName: rpcName, viewerID: viewerID) {
            return
        }
        do {
            let repo = ViewerSyncStateRepository(rpc: rpc)
            let response = try await ViewerSyncTransportTimeout.run {
                try await repo.loadSyncState()
            }
            guard response.meta.viewer_id == viewerID else { return }
            ViewerSyncStateDiskCache.save(response.fingerprints)
            #if DEBUG
            SyncStateProbe.logServer(response.fingerprints)
            #endif
        } catch {
            if BackendV2RpcCompat.isRpcUnavailable(error, rpcName: rpcName) {
                await BackendV2RpcAvailability.shared.markUnavailable(rpcName: rpcName, viewerID: viewerID)
            }
        }
    }

    @MainActor
    static func captureAfterBootstrap(viewerID: String, rpc: any RPCClient) {
        guard BackendV2FeatureFlags.isEnabled(.viewerSyncState) else { return }
        Task {
            await refreshFromServer(viewerID: viewerID, rpc: rpc)
        }
    }
}
