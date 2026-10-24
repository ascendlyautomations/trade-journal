import Foundation

/// Single owner trade deletion path — Trade Detail, journal cards, profile cards.
@MainActor
enum OwnerTradeDeletionService {
    static func deleteOwnedTrade(
        tradeID: TradeID,
        owner: ProfileID,
        previous: Trade?,
        trades: any TradeRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        tradeDetailRepository: any TradeDetailRepository
    ) async throws {
        guard let viewer = await session.currentUserID else {
            throw AppError.domain(.permission(.notAuthenticated))
        }
        let viewerProfile = ProfileID(viewer.rawValue)
        guard viewerProfile == owner else {
            throw AppError.domain(.permission(.notOwner))
        }
        try await trades.delete(id: tradeID)
        detailCache.removeTrade(id: tradeID)
        await tradeDetailRepository.evict(tradeID: tradeID)
        TradeJournalMutationStore.shared.noteDeleted(
            id: tradeID,
            owner: viewerProfile,
            previous: previous
        )
    }
}

/// Context menus dismiss asynchronously; defer delete confirmation state so the dialog presents.
enum TradeDeleteConfirmationPresenter {
    @MainActor
    static func scheduleConfirmation(_ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            await Task.yield()
            action()
        }
    }
}
