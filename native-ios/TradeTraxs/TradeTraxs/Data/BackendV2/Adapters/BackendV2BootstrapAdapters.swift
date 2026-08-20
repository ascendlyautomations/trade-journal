import Foundation

/**
 Backend V2 bootstrap adapter protocols (Phase 1).

 Future cutover:
   Screen → *BootstrapProviding
            ├─ *RestBootstrapRepository
            └─ *RpcBootstrapRepository

 Existing Domain repositories are untouched. These protocols are not registered
 in CompositionRoot yet.
 */

nonisolated protocol SessionBootstrapProviding: Sendable {
    func loadSessionBootstrap() async throws -> SessionBootstrapV1
}

nonisolated protocol DashboardBootstrapProviding: Sendable {
    func loadDashboardBootstrap(accountID: String?) async throws -> DashboardBootstrapV1
}

nonisolated protocol FeedBootstrapProviding: Sendable {
    func loadFeedBootstrap(
        scope: String,
        contentFilter: String?,
        cursor: String?,
        limit: Int?
    ) async throws -> FeedBootstrapV1
}

nonisolated protocol ProfileBootstrapProviding: Sendable {
    func loadProfileBootstrap(
        profileID: String?,
        username: String?
    ) async throws -> ProfileBootstrapV1
}

nonisolated protocol MessagesBootstrapProviding: Sendable {
    func loadMessagesBootstrap() async throws -> MessagesBootstrapV1
}

nonisolated protocol RoomsBootstrapProviding: Sendable {
    func loadRoomBootstrap(
        roomID: String,
        cursor: String?
    ) async throws -> RoomsBootstrapV1
}

nonisolated protocol ActivityBootstrapProviding: Sendable {
    func loadActivityBootstrap(
        cursor: String?,
        limit: Int?
    ) async throws -> ActivityBootstrapV1
}

nonisolated protocol ExploreBootstrapProviding: Sendable {
    func loadExploreBootstrap() async throws -> ExploreBootstrapV1
}

nonisolated protocol LeaderboardBootstrapProviding: Sendable {
    func loadLeaderboardBootstrap(
        timeframe: String,
        category: String,
        cursor: String?
    ) async throws -> LeaderboardBootstrapV1
}

nonisolated protocol CalendarBootstrapProviding: Sendable {
    func loadCalendarBootstrap(
        year: Int,
        month: Int,
        accountID: String?
    ) async throws -> CalendarBootstrapV1
}

nonisolated protocol TradeDetailBootstrapProviding: Sendable {
    func loadTradeDetailBootstrap(tradeID: String) async throws -> TradeDetailBootstrapV1
}

nonisolated protocol SettingsBootstrapProviding: Sendable {
    func loadSettingsBootstrap() async throws -> SettingsBootstrapV1
}

/// Placeholder Rpc adapter — throws until a future phase implements SQL RPCs.
nonisolated struct UnimplementedRpcBootstrapRepository:
    SessionBootstrapProviding,
    DashboardBootstrapProviding,
    FeedBootstrapProviding,
    ProfileBootstrapProviding,
    MessagesBootstrapProviding,
    RoomsBootstrapProviding,
    ActivityBootstrapProviding,
    ExploreBootstrapProviding,
    LeaderboardBootstrapProviding,
    CalendarBootstrapProviding,
    TradeDetailBootstrapProviding,
    SettingsBootstrapProviding
{
    func loadSessionBootstrap() async throws -> SessionBootstrapV1 {
        // Prefer SessionRpcBootstrapRepository when wiring DI (flag ON).
        throw BackendV2RPCError.notImplemented("SessionRpcBootstrapRepository")
    }

    func loadDashboardBootstrap(accountID: String?) async throws -> DashboardBootstrapV1 {
        _ = accountID
        throw BackendV2RPCError.notImplemented("DashboardRpcBootstrapRepository")
    }

    func loadFeedBootstrap(
        scope: String,
        contentFilter: String?,
        cursor: String?,
        limit: Int?
    ) async throws -> FeedBootstrapV1 {
        _ = (scope, contentFilter, cursor, limit)
        throw BackendV2RPCError.notImplemented("FeedRpcBootstrapRepository")
    }

    func loadProfileBootstrap(
        profileID: String?,
        username: String?
    ) async throws -> ProfileBootstrapV1 {
        _ = (profileID, username)
        throw BackendV2RPCError.notImplemented("ProfileRpcBootstrapRepository")
    }

    func loadMessagesBootstrap() async throws -> MessagesBootstrapV1 {
        throw BackendV2RPCError.notImplemented("MessagesRpcBootstrapRepository")
    }

    func loadRoomBootstrap(
        roomID: String,
        cursor: String?
    ) async throws -> RoomsBootstrapV1 {
        _ = (roomID, cursor)
        throw BackendV2RPCError.notImplemented("RoomsRpcBootstrapRepository")
    }

    func loadActivityBootstrap(
        cursor: String?,
        limit: Int?
    ) async throws -> ActivityBootstrapV1 {
        _ = (cursor, limit)
        throw BackendV2RPCError.notImplemented("ActivityRpcBootstrapRepository")
    }

    func loadExploreBootstrap() async throws -> ExploreBootstrapV1 {
        throw BackendV2RPCError.notImplemented("ExploreRpcBootstrapRepository")
    }

    func loadLeaderboardBootstrap(
        timeframe: String,
        category: String,
        cursor: String?
    ) async throws -> LeaderboardBootstrapV1 {
        _ = (timeframe, category, cursor)
        throw BackendV2RPCError.notImplemented("LeaderboardRpcBootstrapRepository")
    }

    func loadCalendarBootstrap(
        year: Int,
        month: Int,
        accountID: String?
    ) async throws -> CalendarBootstrapV1 {
        _ = (year, month, accountID)
        throw BackendV2RPCError.notImplemented("CalendarRpcBootstrapRepository")
    }

    func loadTradeDetailBootstrap(tradeID: String) async throws -> TradeDetailBootstrapV1 {
        _ = tradeID
        throw BackendV2RPCError.notImplemented("TradeDetailRpcBootstrapRepository")
    }

    func loadSettingsBootstrap() async throws -> SettingsBootstrapV1 {
        throw BackendV2RPCError.notImplemented("SettingsRpcBootstrapRepository")
    }
}
