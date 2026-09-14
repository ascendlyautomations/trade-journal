import Foundation

#if DEBUG
/// DEBUG manual network/media baseline — Cold Run A vs Warm Run B.
///
/// Log marker: `TRADETRAXS NETWORK SESSION`
enum TradeTraxsNetworkDiagnostic {
    private static var sessionActive = false

    /// `-networkDiagnosticCold` — clears media/API counters and image caches, then starts session.
    static func beginColdRun(data: DataEnvironment) async {
        await resetMediaCaches(data: data)
        resetCounters()
        sessionActive = true
        print("[TradeTraxsNetworkDiagnostic] Cold Run A — caches cleared, session started.")
    }

    /// `-networkDiagnosticWarm` — starts session without clearing persistent image cache.
    static func beginWarmRun() {
        resetCounters()
        sessionActive = true
        print("[TradeTraxsNetworkDiagnostic] Warm Run B — session started (caches preserved).")
    }

    static func endSessionAndPrint() {
        guard sessionActive else {
            print("[TradeTraxsNetworkDiagnostic] No active session — call beginColdRun or beginWarmRun first.")
            return
        }
        sessionActive = false
        print(buildReport())
    }

    static func resetCounters() {
        SupabaseSessionUsage.beginSession()
        SessionNetworkProbe.resetForTesting()
        MediaEgressTracker.resetSessionCounters()
    }

    static func resetMediaCaches(data: DataEnvironment) async {
        await data.cache.images.removeAllImages()
        MediaURLSession.shared.configuration.urlCache?.removeAllCachedResponses()
        FeedImagePrefetch.cancelAll()
    }

    private static func buildReport() -> String {
        let api = SupabaseSessionUsage.snapshot()
        let image = MediaEgressTracker.sessionSnapshot()

        let apiDownloadMB = Double(api.bytesTransferred) / 1_048_576.0
        let imageNetworkMB = Double(image.imageNetworkBytes) / 1_048_576.0
        let videoNetworkMB = Double(image.videoNetworkBytes) / 1_048_576.0
        let totalDownloadMB = apiDownloadMB + imageNetworkMB + videoNetworkMB

        let memoryHits = image.imageMemoryCacheHits
        let diskHits = image.imageDiskCacheHits
        let misses = image.imageCacheMisses
        let cacheLookups = memoryHits + diskHits + misses
        let memoryHitRate = cacheLookups > 0 ? Double(memoryHits) / Double(cacheLookups) : 0
        let diskHitRate = cacheLookups > 0 ? Double(diskHits) / Double(cacheLookups) : 0
        let missRate = cacheLookups > 0 ? Double(misses) / Double(cacheLookups) : 0

        return """
        TRADETRAXS NETWORK SESSION

        API
        Requests: \(api.totalDatabaseRequests)
        Downloaded: \(String(format: "%.3f MB", apiDownloadMB))
        Uploaded: 0.000 MB

        IMAGES
        Network requests: \(image.imageNetworkRequests)
        Network MB: \(String(format: "%.3f", imageNetworkMB))
        Memory hits: \(memoryHits)
        Disk hits: \(diskHits)
        Misses: \(misses)
        Coalesced: \(image.imageCoalescedDuplicates)
        Prefetch canceled: \(image.imagePrefetchCancelled)

        VIDEO
        Network MB: \(String(format: "%.3f", videoNetworkMB))
        Playback requests: \(image.videoNetworkRequests)

        CACHE
        Memory hit rate: \(String(format: "%.1f%%", memoryHitRate * 100))
        Disk hit rate: \(String(format: "%.1f%%", diskHitRate * 100))
        Network miss rate: \(String(format: "%.1f%%", missRate * 100))

        TOTAL
        Network downloaded: \(String(format: "%.3f MB", totalDownloadMB))
        Network uploaded: 0.000 MB
        """
    }
}
#else
enum TradeTraxsNetworkDiagnostic {
    static func beginColdRun(data: DataEnvironment) async {}
    static func beginWarmRun() {}
    static func endSessionAndPrint() {}
}
#endif
