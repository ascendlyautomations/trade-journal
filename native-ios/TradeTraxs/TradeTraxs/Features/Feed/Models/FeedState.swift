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
    /// Precomputed visible rows — avoids O(n) filtering during SwiftUI body evaluation.
    var cachedVisibleEntries: [FeedTimelineEntry] = []
    var cachedVisibleEntryIDs: [String] = []
    var stories: [Story] = []
    var scope: FeedScope = .global
    var contentFilter: FeedContentFilter = .all
    var viewerID: ProfileID?

    var nextCursor: String?
    var hasMore = true
    var isRefreshing = false
    var isLoadingMore = false
    var didBootstrap = false
    var lastUpdated: Date?
    /// True while a scope/filter reload is in flight — suppress false empty states.
    var isQueryReloadInProgress = false
    /// Filter cache keys confirmed empty by an authoritative first-page load this session.
    var knownEmptyFilterKeys: Set<String> = []

    mutating func rebuildVisibleEntries(
        blockedPeerIDs: Set<ProfileID>,
        viewerID: ProfileID? = nil
    ) {
        var filtered = entries.filter { $0.matches(filter: contentFilter) }
        if let viewerID {
            filtered = filtered.filter { $0.authorProfileID != viewerID }
        }
        if blockedPeerIDs.isEmpty {
            cachedVisibleEntries = filtered
        } else {
            cachedVisibleEntries = filtered.filter { !blockedPeerIDs.contains($0.authorProfileID) }
        }
        cachedVisibleEntryIDs = cachedVisibleEntries.map(\.id)
    }

    var showsEmpty: Bool {
        guard phase == .loaded, !isQueryReloadInProgress else { return false }
        guard cachedVisibleEntries.isEmpty else { return false }
        guard let key = Self.firstPageCacheKey(viewerID: viewerID, scope: scope, contentFilter: contentFilter) else {
            return false
        }
        return knownEmptyFilterKeys.contains(key)
    }

    static func firstPageCacheKey(
        viewerID: ProfileID?,
        scope: FeedScope,
        contentFilter: FeedContentFilter
    ) -> String? {
        guard let viewerID else { return nil }
        return FeedSessionStore.cacheKey(
            viewerID: viewerID,
            scope: scope,
            contentFilter: contentFilter,
            cursor: nil
        )
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
