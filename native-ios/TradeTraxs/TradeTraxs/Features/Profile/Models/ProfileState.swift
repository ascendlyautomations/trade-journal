import Foundation

/// Snapshot of Profile bootstrap output — single source of truth for the screen.
///
/// ``ProfileScreenViewModel`` owns mutation. Section ViewModels apply this snapshot;
/// they do not perform the initial repository work.
struct ProfileState: Equatable {
    enum Phase: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case failed
    }

    var phase: Phase = .idle
    var profileID: ProfileID?
    var profile: Profile?
    var stats: ProfileStats?
    var isOwner = false
    var isFollowing = false
    var ownedTradeRoom: TradeRoom?
    var didResolveTradeRoom = false

    var trades: [Trade] = []
    var tradesNextCursor: String?
    var accountNames: [TradingAccountID: String] = [:]
    /// Owner-only display — never render on public Profile surfaces.
    var accountNumbers: [TradingAccountID: String] = [:]
    var accountModes: [TradingAccountID: TradingAccountMode] = [:]
    var accountSizes: [TradingAccountID: Decimal] = [:]

    var posts: [Post] = []
    var clips: [Reel] = []
    var achievements: [Achievement] = []

    var errorMessage: String?
    var didBootstrap = false
    var isRefreshing = false
    var lastUpdated: Date?

    /// Header metrics derived from ``stats`` (same presentation as today).
    var headerMetrics: [ProfileHeaderMetric] {
        ProfileDisplay.headerMetrics(from: stats)
    }

    var payoutTotal: Decimal? { stats?.payoutTotal }
}

extension ProfileState: ScreenStateModeling {
    var screenPhase: ScreenPhase {
        switch phase {
        case .idle: return .idle
        case .loading: return .loading
        case .loaded: return .loaded
        case .failed: return .failed(errorMessage)
        }
    }

    var screenErrorMessage: String? { errorMessage }

    var pagination: ScreenPaginationSnapshot {
        ScreenPaginationSnapshot(
            nextCursor: tradesNextCursor,
            hasMore: tradesNextCursor != nil,
            isLoadingMore: false
        )
    }
}
