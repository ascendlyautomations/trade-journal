import Foundation

/// Snapshot of Leaderboard bootstrap / screen state — single source of truth.
struct LeaderboardState: Equatable {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    var phase: Phase = .idle
    var audience: LeaderboardAudience = .all
    var timeframe: LeaderboardTimeframe = .month
    var category: LeaderboardCategory = .pnl

    /// Full ranked rows after audience/category presentation transforms.
    var rows: [LeaderboardRow] = []
    /// Top three for the podium (subset of ``rows``).
    var podium: [LeaderboardRow] = []
    /// Remaining list after podium.
    var listRows: [LeaderboardRow] = []
    /// Pinned “You” strip when the viewer is outside the visible list.
    var pinnedViewer: LeaderboardRow?

    var viewerID: ProfileID?
    var followingIDs: Set<ProfileID> = []
    var friendIDs: Set<ProfileID> = []

    var nextCursor: String?
    var hasMore = false
    var isRefreshing = false
    var isLoadingMore = false
    var didBootstrap = false
    var lastUpdated: Date?
    var didPlayPodiumEntrance = false

    var showsEmpty: Bool {
        phase == .loaded && rows.isEmpty
    }
}

extension LeaderboardState: ScreenStateModeling {
    var screenPhase: ScreenPhase {
        switch phase {
        case .idle: return .idle
        case .loading: return .loading
        case .loaded: return .loaded
        case .failed(let message): return .failed(message)
        }
    }

    var screenErrorMessage: String? {
        if case .failed(let message) = phase { return message }
        return nil
    }

    var pagination: ScreenPaginationSnapshot {
        ScreenPaginationSnapshot(
            nextCursor: nextCursor,
            hasMore: hasMore,
            isLoadingMore: isLoadingMore
        )
    }
}
