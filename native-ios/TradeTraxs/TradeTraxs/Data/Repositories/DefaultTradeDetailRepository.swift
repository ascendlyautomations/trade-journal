import Foundation

/// Authoritative TradeDetail — PostgREST `ownerJournalSelect` (production detail source).
nonisolated struct DefaultTradeDetailRepository: TradeDetailRepository {
    private let trades: any TradeRepository
    private let session: any SessionProviding
    private let store: TradeDetailSessionStore
    private let detailCache: DetailPresentationCache?

    init(
        trades: any TradeRepository,
        session: any SessionProviding,
        store: TradeDetailSessionStore = .shared,
        detailCache: DetailPresentationCache? = nil
    ) {
        self.trades = trades
        self.session = session
        self.store = store
        self.detailCache = detailCache
    }

    func cachedDetail(tradeID: TradeID) async -> TradeDetail? {
        let viewerKey = await TradeDetailSessionStore.viewerKey(from: session)
        if let cached = await store.cachedDetail(tradeID: tradeID, viewerKey: viewerKey) {
            #if DEBUG
            await MainActor.run {
                TradeDetailTelemetry.cacheHit(tradeID: tradeID, viewer: viewerKey)
            }
            #endif
            return cached
        }
        return nil
    }

    func load(
        tradeID: TradeID,
        policy: TradeDetailLoadPolicy
    ) async throws -> TradeDetail {
        let viewerKey = await TradeDetailSessionStore.viewerKey(from: session)
        #if DEBUG
        await MainActor.run {
            TradeDetailTelemetry.load(tradeID: tradeID, viewer: viewerKey)
        }
        #endif

        if !policy.forceNetwork, let cached = await store.cachedDetail(tradeID: tradeID, viewerKey: viewerKey) {
            await MainActor.run {
                detailCache?.seedAuthoritativeDetail(cached, authority: .authoritativeNetwork)
            }
            return cached
        }

        if policy.forceNetwork {
            await store.evict(tradeID: tradeID, viewerKey: viewerKey)
        }

        let detail: TradeDetail
        do {
            detail = try await store.loadCoalesced(tradeID: tradeID, viewerKey: viewerKey) {
                let loaded = try await trades.trade(id: tradeID)
                let bytes = TradeDetailPayloadProbe.estimatedUtf8Bytes(for: loaded)
                return (loaded, bytes)
            }
        } catch {
            #if DEBUG
            if Self.looksLikeUnauthorized(error) {
                await MainActor.run {
                    TradeDetailTelemetry.unauthorized(tradeID: tradeID, viewer: viewerKey)
                }
            }
            #endif
            throw error
        }

        await MainActor.run {
            detailCache?.seedAuthoritativeDetail(detail, authority: .authoritativeNetwork)
        }
        return detail
    }

    func replaceCachedDetail(_ detail: TradeDetail, authority: TradeDetailAuthority) async {
        let viewerKey = await TradeDetailSessionStore.viewerKey(from: session)
        await store.store(
            detail,
            tradeID: detail.id,
            viewerKey: viewerKey,
            authority: authority,
            payloadBytes: nil
        )
        await MainActor.run {
            detailCache?.seedAuthoritativeDetail(detail, authority: authority)
        }
    }

    func evict(tradeID: TradeID) async {
        let viewerKey = await TradeDetailSessionStore.viewerKey(from: session)
        await store.evict(tradeID: tradeID, viewerKey: viewerKey)
        #if DEBUG
        await MainActor.run {
            TradeDetailTelemetry.evict(tradeID: tradeID, reason: "explicit")
        }
        #endif
        await MainActor.run {
            detailCache?.evictAuthoritativeDetail(tradeID: tradeID)
        }
    }

    func resetSessionCache() async {
        await store.resetAll()
    }

    private static func looksLikeUnauthorized(_ error: Error) -> Bool {
        let text = String(describing: error).lowercased()
        return text.contains("42501") || text.contains("permission") || text.contains("401")
    }
}
