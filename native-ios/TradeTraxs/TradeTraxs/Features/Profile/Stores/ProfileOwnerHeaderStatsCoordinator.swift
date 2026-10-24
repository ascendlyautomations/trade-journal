import Foundation
import Observation

/// Patches owner Profile header metrics (Trades / Win % / Profit Factor) after journal mutations.
@Observable
@MainActor
final class ProfileOwnerHeaderStatsCoordinator {
    static let shared = ProfileOwnerHeaderStatsCoordinator()

    private weak var detailCache: DetailPresentationCache?
    private weak var currentUserProfile: CurrentUserProfileStore?
    private var profiles: (any ProfileRepository)?
    private weak var activeProfileScreen: ProfileScreenViewModel?

    private init() {}

    func configure(
        detailCache: DetailPresentationCache,
        currentUserProfile: CurrentUserProfileStore,
        profiles: any ProfileRepository
    ) {
        self.detailCache = detailCache
        self.currentUserProfile = currentUserProfile
        self.profiles = profiles
    }

    func registerActiveProfile(screen: ProfileScreenViewModel) {
        activeProfileScreen = screen
    }

    func unregisterActiveProfile(screen: ProfileScreenViewModel) {
        if activeProfileScreen === screen {
            activeProfileScreen = nil
        }
    }

    /// Recompute header trade metrics from the session owner journal (canonical ``ProfileOverviewMetrics``).
    ///
    /// A partial owner-trade cache must not replace loaded header metrics with a smaller overview.
    /// `publicOverviewDelta` adjusts the existing count when the cache cannot see the full journal.
    func reconcile(ownerID: ProfileID, publicOverviewDelta: Int = 0) {
        let trades = SessionOwnerTradesStore.shared.cached(for: ownerID) ?? []
        let overview = ProfileOverviewMetrics.overview(fromPublicJournal: trades)

        let loaded = loadedStats(ownerID: ownerID)
        if let loaded,
           loaded.hasLoadedHeaderMetrics,
           overview.publicTradeCount < loaded.publicTradeCount
        {
            guard publicOverviewDelta != 0 else { return }
            var kept = loaded
            kept.publicTradeCount = max(0, loaded.publicTradeCount + publicOverviewDelta)
            kept.tradeCount = max(0, loaded.tradeCount + publicOverviewDelta)
            publish(kept)
            return
        }

        guard let stats = statsApplying(overview, to: loaded, ownerID: ownerID) else { return }
        profiles?.invalidateCachedStats(for: ownerID)
        publish(stats)
    }

    private func publish(_ stats: ProfileStats) {
        detailCache?.seed(stats: stats)
        currentUserProfile?.applyOwnerJournalHeaderMetrics(stats)
        activeProfileScreen?.applyExternalOwnerHeaderStats(stats)
    }

    private func loadedStats(ownerID: ProfileID) -> ProfileStats? {
        let base =
            detailCache?.stats(for: ownerID)
            ?? (currentUserProfile?.profile?.id == ownerID ? currentUserProfile?.stats : nil)
            ?? activeProfileScreen?.state.stats
        guard let base, base.profileID == ownerID else { return nil }
        return base
    }

    private func statsApplying(
        _ overview: ProfileOverviewMetrics.Result,
        to loaded: ProfileStats?,
        ownerID: ProfileID
    ) -> ProfileStats? {
        var stats = loaded ?? ProfileStats(
            profileID: ownerID,
            followerCount: 0,
            followingCount: 0,
            postCount: 0,
            tradeCount: 0,
            publicTradeCount: 0,
            payoutTotal: nil
        )
        guard stats.profileID == ownerID else { return nil }
        stats.tradeCount = overview.publicTradeCount
        stats.publicTradeCount = overview.publicTradeCount
        stats.winRate = overview.winRate
        stats.profitFactor = overview.profitFactor
        stats.netPnL = overview.netPnL
        stats.averageRR = overview.averageRR
        if stats.expectancy == nil {
            stats.expectancy = overview.expectancy
        }
        return stats
    }
}
