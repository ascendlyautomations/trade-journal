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
        if let viewer = await session.currentUserID {
            if !viewer.rawValue.hasPrefix("dev.") {
                try await trades.delete(id: tradeID)
            }
        } else {
            throw AppError.domain(.permission(.notAuthenticated))
        }
        detailCache.removeTrade(id: tradeID)
        await tradeDetailRepository.evict(tradeID: tradeID)
        TradeJournalMutationStore.shared.noteDeleted(
            id: tradeID,
            owner: owner,
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
