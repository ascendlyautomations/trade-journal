import Foundation

nonisolated struct GettingStartedRpcRepository {
    private let client: BackendV2RPCClient

    init(rpc: any RPCClient) {
        self.client = BackendV2RPCClient(transport: rpc)
    }

    func loadSignals() async throws -> GettingStartedSignals {
        let wire = try await client.call(
            .gettingStarted,
            argumentsJSON: Data("{}".utf8),
            as: GettingStartedSignalsWire.self,
            options: BackendV2RPCCallOptions(
                cacheMiss: true,
                flagName: BackendV2FeatureFlag.gettingStarted.dottedName
            )
        )
        return GettingStartedSignalsDecoder.map(wire)
    }
}

enum GettingStartedLoader {
    enum LoaderError: Error, Sendable {
        case flagOff
        case notAuthenticated
        case rpcUnavailable
    }

    @MainActor
    static func load(
        viewerID: ProfileID,
        rpc: any RPCClient
    ) async throws -> GettingStartedSignals {
        guard BackendV2FeatureFlags.isEnabled(.gettingStarted) else {
            throw LoaderError.flagOff
        }

        let rpcName = BackendV2Versioning.RPCName.gettingStarted.rawValue
        if await BackendV2RpcAvailability.shared.isUnavailable(rpcName: rpcName, viewerID: viewerID.rawValue) {
            throw LoaderError.rpcUnavailable
        }

        let flightKey = BackendV2FlightKeys.gettingStarted(viewerID: viewerID.rawValue)
        do {
            let data = try await BackendV2SingleFlight.shared.coalesce(key: flightKey) {
                try await rpc.call(
                    functionName: BackendV2Versioning.RPCName.gettingStarted.rawValue,
                    jsonBody: Data("{}".utf8)
                )
            }
            return try GettingStartedSignalsDecoder.decode(data)
        } catch {
            if BackendV2RpcCompat.isRpcUnavailable(error, rpcName: rpcName) {
                await BackendV2RpcAvailability.shared.markUnavailable(
                    rpcName: rpcName,
                    viewerID: viewerID.rawValue
                )
                throw LoaderError.rpcUnavailable
            }
            throw error
        }
    }
}
