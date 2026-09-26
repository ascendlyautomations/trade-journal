import Foundation

/// Release-safe bounded aggregates for Clips video delivery (no per-byte logs).
nonisolated enum ClipVideoDeliveryTelemetry {
    enum Event: Sendable {
        case clipStart
        case clipCompletedView
        case playbackSeconds(Double)
        case networkBackedLoad
        case persistentCacheHit
        case persistentCacheMiss
        case bytesWrittenToCache(Int64)
        case cacheReuse
        case prefetchStarted
        case prefetchViewed
        case prefetchDiscarded
        case repeatReentryReuse
        case cacheFillStarted
        case cacheFillCompleted
        case cacheFillCancelled
        case prefetchFullDownload
    }

    struct Aggregates: Sendable, Equatable {
        var clipStarts: Int = 0
        var completedViews: Int = 0
        var playbackSeconds: Double = 0
        var networkBackedLoads: Int = 0
        var persistentCacheHits: Int = 0
        var persistentCacheMisses: Int = 0
        var bytesWrittenToCache: Int64 = 0
        var cacheReuses: Int = 0
        var prefetchStarted: Int = 0
        var prefetchViewed: Int = 0
        var prefetchDiscarded: Int = 0
        var repeatReentryReuses: Int = 0
        var cacheFillStarted: Int = 0
        var cacheFillCompleted: Int = 0
        var cacheFillCancelled: Int = 0
        var prefetchFullDownloads: Int = 0
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var aggregates = Aggregates()
    nonisolated(unsafe) private static var viewerSessionID = UUID().uuidString

    nonisolated static func resetViewerSession() {
        lock.lock()
        aggregates = Aggregates()
        viewerSessionID = UUID().uuidString
        lock.unlock()
        ClipVideoByteAccounting.resetSession()
        ClipVideoTransferTelemetry.resetSession()
    }

    nonisolated static func record(_ event: Event) {
        lock.lock()
        defer { lock.unlock() }
        switch event {
        case .clipStart:
            aggregates.clipStarts += 1
        case .clipCompletedView:
            aggregates.completedViews += 1
        case .playbackSeconds(let seconds):
            guard seconds > 0 else { return }
            aggregates.playbackSeconds += seconds
        case .networkBackedLoad:
            aggregates.networkBackedLoads += 1
        case .persistentCacheHit:
            aggregates.persistentCacheHits += 1
        case .persistentCacheMiss:
            aggregates.persistentCacheMisses += 1
        case .bytesWrittenToCache(let bytes):
            guard bytes > 0 else { return }
            aggregates.bytesWrittenToCache += bytes
        case .cacheReuse:
            aggregates.cacheReuses += 1
        case .prefetchStarted:
            aggregates.prefetchStarted += 1
        case .prefetchViewed:
            aggregates.prefetchViewed += 1
        case .prefetchDiscarded:
            aggregates.prefetchDiscarded += 1
        case .repeatReentryReuse:
            aggregates.repeatReentryReuses += 1
        case .cacheFillStarted:
            aggregates.cacheFillStarted += 1
        case .cacheFillCompleted:
            aggregates.cacheFillCompleted += 1
        case .cacheFillCancelled:
            aggregates.cacheFillCancelled += 1
        case .prefetchFullDownload:
            aggregates.prefetchFullDownloads += 1
        }
    }

    nonisolated static func snapshot() -> Aggregates {
        lock.lock()
        defer { lock.unlock() }
        return aggregates
    }

    nonisolated static func currentViewerSessionID() -> String {
        lock.lock()
        defer { lock.unlock() }
        return viewerSessionID
    }

    nonisolated static func logSessionSummary(context: String = "clips") {
        let session = currentViewerSessionID()
        let snap = snapshot()
        print(
            """
            [ClipDelivery] summary context=\(context) viewerSession=\(session) \
            starts=\(snap.clipStarts) completed=\(snap.completedViews) \
            playbackSec=\(String(format: "%.1f", snap.playbackSeconds)) \
            networkLoads=\(snap.networkBackedLoads) cacheHits=\(snap.persistentCacheHits) \
            cacheMisses=\(snap.persistentCacheMisses) cacheReuses=\(snap.cacheReuses) \
            bytesWritten=\(snap.bytesWrittenToCache) cacheFillStarted=\(snap.cacheFillStarted) \
            cacheFillCompleted=\(snap.cacheFillCompleted) cacheFillCancelled=\(snap.cacheFillCancelled) \
            prefetchStarted=\(snap.prefetchStarted) prefetchViewed=\(snap.prefetchViewed) \
            prefetchDiscarded=\(snap.prefetchDiscarded) prefetchFullDownloads=\(snap.prefetchFullDownloads) \
            reentryReuse=\(snap.repeatReentryReuses)
            """
        )
    }
}

#if DEBUG
nonisolated enum ClipVideoDeliveryTrace {
    nonisolated static func log(
        _ message: String,
        cacheHit: Bool? = nil,
        source: String? = nil,
        assetBytes: Int64? = nil,
        bytesDownloaded: Int64? = nil,
        prefetch: Bool? = nil,
        reused: Bool? = nil,
        cacheFillEligible: Bool? = nil,
        cacheFillStarted: Bool? = nil,
        cacheFillReason: String? = nil,
        watchedSeconds: Double? = nil,
        watchedPercent: Double? = nil
    ) {
        var parts = ["[ClipDelivery]", message]
        if let source { parts.append("source=\(source)") }
        if let cacheHit { parts.append("cacheHit=\(cacheHit)") }
        if let cacheFillEligible { parts.append("cacheFillEligible=\(cacheFillEligible)") }
        if let cacheFillStarted { parts.append("cacheFillStarted=\(cacheFillStarted)") }
        if let cacheFillReason { parts.append("cacheFillReason=\(cacheFillReason)") }
        if let watchedSeconds { parts.append("watchedSeconds=\(String(format: "%.2f", watchedSeconds))") }
        if let watchedPercent { parts.append("watchedPercent=\(String(format: "%.3f", watchedPercent))") }
        if let assetBytes { parts.append("assetBytes=\(assetBytes)") }
        if let bytesDownloaded { parts.append("bytesDownloaded=\(bytesDownloaded)") }
        if let prefetch { parts.append("prefetch=\(prefetch)") }
        if let reused { parts.append("reused=\(reused)") }
        parts.append("viewerSession=\(ClipVideoDeliveryTelemetry.currentViewerSessionID())")
        print(parts.joined(separator: " "))
    }

    nonisolated static func cache(_ message: String) {
        print("[ClipCache] \(message) viewerSession=\(ClipVideoDeliveryTelemetry.currentViewerSessionID())")
    }
}

nonisolated enum ClipPrefetchTrace {
    nonisolated static func started(clipID: String, fullCacheDownloadStarted: Bool) {
        print(
            """
            [ClipPrefetch] clipID=\(clipID) started=true becameActive=false discarded=false \
            fullCacheDownloadStarted=\(fullCacheDownloadStarted)
            """
        )
    }

    nonisolated static func becameActive(clipID: String) {
        print("[ClipPrefetch] clipID=\(clipID) becameActive=true")
    }

    nonisolated static func discarded(clipID: String) {
        print("[ClipPrefetch] clipID=\(clipID) discarded=true")
    }
}
#else
nonisolated enum ClipVideoDeliveryTrace {
    nonisolated static func log(
        _ message: String,
        cacheHit: Bool? = nil,
        source: String? = nil,
        assetBytes: Int64? = nil,
        bytesDownloaded: Int64? = nil,
        prefetch: Bool? = nil,
        reused: Bool? = nil,
        cacheFillEligible: Bool? = nil,
        cacheFillStarted: Bool? = nil,
        cacheFillReason: String? = nil,
        watchedSeconds: Double? = nil,
        watchedPercent: Double? = nil
    ) {}

    nonisolated static func cache(_ message: String) {}
}

nonisolated enum ClipPrefetchTrace {
    nonisolated static func started(clipID: String, fullCacheDownloadStarted: Bool) {}
    nonisolated static func becameActive(clipID: String) {}
    nonisolated static func discarded(clipID: String) {}
}
#endif
