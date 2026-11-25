import Foundation

nonisolated struct LeaderboardRpcCurveRepository {
    private let client: BackendV2RPCClient

    init(rpc: any RPCClient) {
        self.client = BackendV2RPCClient(transport: rpc)
    }

    func loadLeaderboardCurve(
        timeframe: String,
        category: String,
        audience: String
    ) async throws -> LeaderboardCurveV1 {
        let args = LeaderboardCurveRpcArguments(
            p_timeframe: timeframe,
            p_category: category,
            p_audience: audience
        )
        let body = try JSONEncoder().encode(args)
        let value = try await client.call(
            .leaderboardCurve,
            argumentsJSON: body,
            as: LeaderboardCurveV1.self,
            options: BackendV2RPCCallOptions(
                cacheMiss: true,
                flagName: BackendV2FeatureFlag.leaderboard.dottedName
            )
        )
        try value.validateContractVersion()
        return value
    }
}

private nonisolated struct LeaderboardCurveRpcArguments: Encodable, Sendable {
    var p_timeframe: String
    var p_category: String
    var p_audience: String
}

enum LeaderboardCurveLoader {
    enum LoaderError: Error, Sendable {
        case flagOff
        case rpcUnavailable
        case unsupported
    }

    struct Applied: Sendable, Equatable {
        var points: [LeaderboardCurveChartPoint]
        var metricFormat: LeaderboardCurveV1.MetricFormat
        var supported: Bool
    }

    @MainActor
    static func load(
        viewerID: ProfileID?,
        timeframe: LeaderboardTimeframe,
        category: LeaderboardCategory,
        audience: LeaderboardAudience,
        rpc: any RPCClient,
        forceNetwork: Bool
    ) async throws -> Applied {
        _ = forceNetwork
        guard category.supportsCurveChart else {
            throw LoaderError.unsupported
        }
        guard BackendV2FeatureFlags.isEnabled(.leaderboard) else {
            throw LoaderError.flagOff
        }

        let rpcName = BackendV2Versioning.RPCName.leaderboardCurve.rawValue
        if let viewerID,
           await BackendV2RpcAvailability.shared.isUnavailable(
               rpcName: rpcName,
               viewerID: viewerID.rawValue
           )
        {
            throw LoaderError.rpcUnavailable
        }

        let flightKey = BackendV2FlightKeys.leaderboardCurve(
            timeframe: timeframe.rpcValue,
            category: category.rawValue,
            audience: audience.rawValue
        )

        let bootstrap: LeaderboardCurveV1
        do {
            let data = try await BootstrapTransportTimeout.run {
                try await BackendV2SingleFlight.shared.coalesce(key: flightKey) {
                    let repo = LeaderboardRpcCurveRepository(rpc: rpc)
                    let value = try await repo.loadLeaderboardCurve(
                        timeframe: timeframe.rpcValue,
                        category: category.rawValue,
                        audience: audience.rawValue
                    )
                    return try JSONEncoder().encode(value)
                }
            }
            bootstrap = try JSONDecoder().decode(LeaderboardCurveV1.self, from: data)
        } catch {
            if BackendV2RpcCompat.isRpcUnavailable(error, rpcName: rpcName) {
                if let viewerID {
                    await BackendV2RpcAvailability.shared.markUnavailable(
                        rpcName: rpcName,
                        viewerID: viewerID.rawValue
                    )
                }
                throw LoaderError.rpcUnavailable
            }
            throw error
        }

        guard bootstrap.data.supported else {
            throw LoaderError.unsupported
        }

        let points = LeaderboardCurveChartData.preparePoints(from: bootstrap.data.points)

        return Applied(
            points: points,
            metricFormat: bootstrap.data.metric_format,
            supported: true
        )
    }
}