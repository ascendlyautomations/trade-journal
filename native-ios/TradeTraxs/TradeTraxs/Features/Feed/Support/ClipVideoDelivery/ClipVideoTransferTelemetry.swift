import Foundation

/// Phase 12C — transfer ownership and cache-fill decisions (release-safe aggregates + DEBUG lines).
nonisolated enum ClipVideoTransferTelemetry {
    enum NetworkOwner: String, Sendable {
        case avplayer
        case deliveryService
        case shared
    }

    enum PersistentCacheResult: String, Sendable {
        case written
        case skippedDuplicateRisk
        case alreadyCached
        case failed
    }

    enum Strategy: String, Sendable {
        case avplayerProgressive
        case deliveryFullDownload
        case duplicateRiskSkip
        case diskReuse
    }

    enum CacheFillDecisionKind: String, Sendable {
        case pending
        case startFill
        case skipDuplicateRisk
        case cancelFillDuplicateRisk
        case alreadyCached
        case unknown
    }

    enum CacheDecisionStage: String, Sendable {
        case initial
        case reevaluation
        case final
    }

    struct SessionTotals: Sendable, Equatable {
        var avPlayerBytesObserved: Int64 = 0
        var cacheFillBytes: Int64 = 0
        var estimatedDuplicateBytes: Int64 = 0
        var clipsPersisted: Int = 0
        var duplicateRiskSkips: Int = 0
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var totals = SessionTotals()

    nonisolated static func resetSession() {
        lock.lock()
        totals = SessionTotals()
        lock.unlock()
    }

    nonisolated static func recordAVPlayerBytes(_ bytes: Int64) {
        guard bytes > 0 else { return }
        lock.lock()
        totals.avPlayerBytesObserved += bytes
        lock.unlock()
    }

    nonisolated static func recordCacheFillBytes(_ bytes: Int64) {
        guard bytes > 0 else { return }
        lock.lock()
        totals.cacheFillBytes += bytes
        lock.unlock()
    }

    nonisolated static func recordClipPersisted() {
        lock.lock()
        totals.clipsPersisted += 1
        lock.unlock()
    }

    nonisolated static func recordDuplicateRiskSkip(estimatedDuplicateBytes: Int64) {
        lock.lock()
        totals.duplicateRiskSkips += 1
        if estimatedDuplicateBytes > 0 {
            totals.estimatedDuplicateBytes += estimatedDuplicateBytes
        }
        lock.unlock()
    }

    nonisolated static func snapshot() -> SessionTotals {
        lock.lock()
        defer { lock.unlock() }
        return totals
    }

    nonisolated static func logSessionEgressSummary(context: String) {
        let snap = snapshot()
        let assetNetwork = snap.avPlayerBytesObserved + snap.cacheFillBytes
        print(
            """
            [ClipDelivery] egressSummary context=\(context) \
            assetNetworkBytesObserved=\(assetNetwork) \
            avPlayerBytesObserved=\(snap.avPlayerBytesObserved) \
            cacheFillBytes=\(snap.cacheFillBytes) \
            estimatedDuplicateBytes=\(snap.estimatedDuplicateBytes) \
            clipsPersisted=\(snap.clipsPersisted) \
            duplicateRiskSkips=\(snap.duplicateRiskSkips) \
            prefetchFullDownloads=\(ClipVideoDeliveryTelemetry.snapshot().prefetchFullDownloads)
            """
        )
    }

    nonisolated static func logTransferOwnership(
        clipID: String,
        playbackSource: String,
        networkOwner: NetworkOwner,
        assetBytes: Int64?,
        avPlayerObservedBytes: Int64,
        avPlayerRawReportedBytes: Int64? = nil,
        deliveryDownloadBytes: Int64,
        duplicateBytesEstimated: Int64?,
        persistentCacheResult: PersistentCacheResult,
        strategy: Strategy,
        cacheDecisionState: String? = nil
    ) {
        let asset = assetBytes.map(String.init) ?? "unknown"
        let dup = duplicateBytesEstimated.map(String.init) ?? "unknown"
        let raw = avPlayerRawReportedBytes.map(String.init) ?? "unknown"
        let decisionState = cacheDecisionState ?? "unknown"
        print(
            """
            [ClipTransferOwnership] clipID=\(clipID) playbackSource=\(playbackSource) \
            networkOwner=\(networkOwner.rawValue) assetBytes=\(asset) \
            avPlayerObservedBytes=\(avPlayerObservedBytes) avPlayerRawReportedBytes=\(raw) \
            deliveryDownloadBytes=\(deliveryDownloadBytes) \
            duplicateBytesEstimated=\(dup) persistentCacheResult=\(persistentCacheResult.rawValue) \
            strategy=\(strategy.rawValue) cacheDecisionState=\(decisionState)
            """
        )
    }

    nonisolated static func logCacheDecision(
        clipID: String,
        stage: CacheDecisionStage?,
        watchedSeconds: Double,
        watchedPercent: Double?,
        assetBytes: Int64?,
        avPlayerObservedBytes: Int64,
        avPlayerObservedPercent: Double?,
        avPlayerRawReportedBytes: Int64? = nil,
        decision: CacheFillDecisionKind,
        reason: String
    ) {
        let watchedPct = watchedPercent.map { String(format: "%.3f", $0) } ?? "unknown"
        let asset = assetBytes.map(String.init) ?? "unknown"
        let avPct = avPlayerObservedPercent.map { String(format: "%.3f", $0) } ?? "unknown"
        let stageLabel = stage?.rawValue ?? "unknown"
        let raw = avPlayerRawReportedBytes.map(String.init) ?? "unknown"
        print(
            """
            [ClipCacheDecision] clipID=\(clipID) stage=\(stageLabel) \
            watchedSeconds=\(String(format: "%.2f", watchedSeconds)) watchedPercent=\(watchedPct) \
            assetBytes=\(asset) avPlayerObservedBytes=\(avPlayerObservedBytes) \
            avPlayerObservedPercent=\(avPct) rawReportedBytes=\(raw) \
            estimatedUniquePlaybackBytes=\(avPlayerObservedBytes) \
            maximumAVPlayerFractionForFullCacheFill=\(String(format: "%.3f", ClipVideoCacheFillPolicy.maximumAVPlayerFractionForFullCacheFill)) \
            duplicateRiskAvPlayerFraction=\(String(format: "%.3f", ClipVideoCacheFillPolicy.duplicateRiskAvPlayerFraction)) \
            decision=\(decision.rawValue) reason=\(reason)
            """
        )
    }
}
