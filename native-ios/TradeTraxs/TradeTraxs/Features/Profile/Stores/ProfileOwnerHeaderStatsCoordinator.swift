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
    func reconcile(ownerID: ProfileID) {
        let trades = SessionOwnerTradesStore.shared.cached(for: ownerID) ?? []
        let overview = ProfileOverviewMetrics.overview(fromPublicJournal: trades)

        profiles?.invalidateCachedStats(for: ownerID)

        guard let patched = patchExistingStats(ownerID: ownerID, overview: overview) else { return }

        detailCache?.seed(stats: patched)
        currentUserProfile?.applyOwnerJournalHeaderMetrics(patched)
        activeProfileScreen?.applyExternalOwnerHeaderStats(patched)
    }

    private func patchExistingStats(
        ownerID: ProfileID,
        overview: ProfileOverviewMetrics.Result
    ) -> ProfileStats? {
        let base =
            detailCache?.stats(for: ownerID)
            ?? (currentUserProfile?.profile?.id == ownerID ? currentUserProfile?.stats : nil)
            ?? activeProfileScreen?.state.stats

        guard var stats = base, stats.profileID == ownerID else {
            return ProfileStats(
                profileID: ownerID,
                followerCount: 0,
                followingCount: 0,
                postCount: 0,
                tradeCount: overview.publicTradeCount,
                publicTradeCount: overview.publicTradeCount,
                winRate: overview.winRate,
                profitFactor: overview.profitFactor,
                netPnL: overview.netPnL,
                averageRR: overview.averageRR,
                payoutTotal: nil,
                expectancy: overview.expectancy
            )
        }

        stats.tradeCount = overview.publicTradeCount
        stats.publicTradeCount = overview.publicTradeCount
        stats.winRate = overview.winRate
        stats.profitFactor = overview.profitFactor
        stats.netPnL = overview.netPnL
        stats.averageRR = overview.averageRR
        return stats
    }
}
