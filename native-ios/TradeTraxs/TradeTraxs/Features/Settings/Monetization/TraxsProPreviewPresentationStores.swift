import Foundation

/// Separates TraxsPro preview analytics presentation from the live production dashboard.
@MainActor
enum TradingRulesCompliancePresentationStores {
    static let production = TradingRulesComplianceSessionStore.shared
    private(set) static var preview: TradingRulesComplianceSessionStore?
    /// Discarded publishes when preview UI is shown without an active preview environment (never `.shared`).
    private static let unboundPreviewSink = TradingRulesComplianceSessionStore()

    static func bindPreview(_ store: TradingRulesComplianceSessionStore) {
        preview = store
        RulesPreviewDebugLog.log("bindPreview rulesStore=\(RulesPreviewDebugLog.storeID(store))")
    }

    static func clearPreview() {
        if let preview {
            RulesPreviewDebugLog.log(
                "clearPreview resetting store=\(RulesPreviewDebugLog.storeID(preview)) \(RulesPreviewDebugLog.describe(session: preview))"
            )
            preview.reset()
        } else {
            RulesPreviewDebugLog.log("clearPreview no bound preview store")
        }
        preview = nil
    }

    private static func resolvedPreviewStore() -> TradingRulesComplianceSessionStore {
        if let preview { return preview }
        if let active = TraxsProPreviewSession.shared.activePreviewEnvironment {
            return active.rulesPresentationStore
        }
        return unboundPreviewSink
    }

    static func store(forPreviewUI: Bool) -> TradingRulesComplianceSessionStore {
        let store = forPreviewUI ? resolvedPreviewStore() : production
        if forPreviewUI {
            RulesPreviewDebugLog.log(
                "store(forPreviewUI: true) -> \(RulesPreviewDebugLog.storeID(store)) boundPreview=\(preview.map { RulesPreviewDebugLog.storeID($0) } ?? "nil") activeEnv=\(RulesPreviewDebugLog.describe(TraxsProPreviewSession.shared.activePreviewEnvironment))"
            )
        }
        return store
    }

    static func isPreviewDataPlane(_ data: DataEnvironment) -> Bool {
        guard let active = TraxsProPreviewSession.shared.activePreviewEnvironment else { return false }
        return active.data.detailCache === data.detailCache
    }

    static func store(for data: DataEnvironment) -> TradingRulesComplianceSessionStore {
        isPreviewDataPlane(data) ? resolvedPreviewStore() : production
    }

    static func isPreviewDetailCache(_ detailCache: DetailPresentationCache) -> Bool {
        guard let active = TraxsProPreviewSession.shared.activePreviewEnvironment else { return false }
        return active.data.detailCache === detailCache
    }

    static func store(detailCache: DetailPresentationCache) -> TradingRulesComplianceSessionStore {
        isPreviewDetailCache(detailCache) ? resolvedPreviewStore() : production
    }
}

@MainActor
enum TradingScorecardPresentationStores {
    static let production = TradingScorecardSessionStore.shared
    private(set) static var preview: TradingScorecardSessionStore?

    static func bindPreview(_ store: TradingScorecardSessionStore) {
        preview = store
    }

    static func clearPreview() {
        preview?.reset()
        preview = nil
    }

    static func store(forPreviewUI: Bool) -> TradingScorecardSessionStore {
        forPreviewUI ? (preview ?? production) : production
    }

    static func store(detailCache: DetailPresentationCache) -> TradingScorecardSessionStore {
        guard let active = TraxsProPreviewSession.shared.activePreviewEnvironment else {
            return production
        }
        return active.data.detailCache === detailCache ? (preview ?? production) : production
    }

    static func store(for data: DataEnvironment) -> TradingScorecardSessionStore {
        store(detailCache: data.detailCache)
    }
}