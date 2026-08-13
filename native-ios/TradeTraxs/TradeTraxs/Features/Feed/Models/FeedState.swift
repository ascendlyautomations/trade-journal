import Foundation

/// Snapshot of Feed bootstrap / screen state — single source of truth for the Feed tab.
///
/// ``FeedScreenViewModel`` owns mutation. Child views render this state and may request
/// pagination / refresh through the screen owner only.
struct FeedState: Equatable {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    var phase: Phase = .idle
    var entries: [FeedTimelineEntry] = []
    var stories: [Story] = []
    var scope: FeedScope = .following
    var contentFilter: FeedContentFilter = .all
    var viewerID: ProfileID?

    var nextCursor: String?
    var hasMore = true
    var isRefreshing = false
    var isLoadingMore = false
    var didBootstrap = false
    var lastUpdated: Date?

    var visibleEntries: [FeedTimelineEntry] {
        entries.filter { $0.matches(filter: contentFilter) }
    }

    var showsEmpty: Bool {
        phase == .loaded && visibleEntries.isEmpty
    }
}

extension FeedState: ScreenStateModeling {
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
