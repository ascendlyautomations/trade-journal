import Foundation

#if DEBUG
/// Phase 12D — AVPlayer network bytes separated from cache fill and diagnostic probes.
nonisolated enum ClipAVPlayerEgressTelemetry {
    private struct ClipEgress {
        var assetBytes: Int64?
        var playerInstances: Int = 0
        var itemInstances: Int = 0
        var playbackRequests: Int = 0
        var playbackBytes: Int64 = 0
        var prefetchBytes: Int64 = 0
        var activeBytes: Int64 = 0
        var loops: Int = 0
        var recreations: Int = 0
        var becameActiveFromPrefetch: Bool = false
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var byClipID: [String: ClipEgress] = [:]

    nonisolated static func resetSession() {
        lock.lock()
        byClipID.removeAll()
        lock.unlock()
    }

    nonisolated static func noteIdentityEvent(clipID: String, event: ClipPlayerIdentityTrace.Event) {
        lock.lock()
        var row = byClipID[clipID, default: ClipEgress()]
        switch event {
        case .createPlayer:
            row.playerInstances += 1
            row.recreations += row.playerInstances > 1 ? 1 : 0
        case .createItem:
            row.itemInstances += 1
        case .promotePrefetchToActive:
            row.becameActiveFromPrefetch = true
        case .loopSeek:
            row.loops += 1
        default:
            break
        }
        byClipID[clipID] = row
        lock.unlock()
    }

    nonisolated static func noteKnownAssetBytes(clipID: String, bytes: Int64) {
        guard bytes > 0 else { return }
        lock.lock()
        var row = byClipID[clipID, default: ClipEgress()]
        row.assetBytes = bytes
        byClipID[clipID] = row
        lock.unlock()
    }

    nonisolated static func knownAssetBytes(for clipID: String) -> Int64? {
        lock.lock()
        defer { lock.unlock() }
        return byClipID[clipID]?.assetBytes
    }

    nonisolated static func recordPlaybackDelta(
        clipID: String,
        role: String,
        deltaBytes: Int64,
        sessionItemBytes: Int64
    ) {
        guard deltaBytes > 0 else { return }
        lock.lock()
        var row = byClipID[clipID, default: ClipEgress()]
        row.playbackRequests += 1
        row.playbackBytes = max(row.playbackBytes, sessionItemBytes)
        if role == "prefetch" {
            row.prefetchBytes += deltaBytes
        } else {
            row.activeBytes += deltaBytes
        }
        byClipID[clipID] = row
        lock.unlock()
    }

    nonisolated static func logClipSummary(clipID: String) {
        lock.lock()
        let row = byClipID[clipID] ?? ClipEgress()
        lock.unlock()
        let asset = row.assetBytes.map(String.init) ?? "unknown"
        let pct: String
        if let assetBytes = row.assetBytes, assetBytes > 0 {
            pct = String(format: "%.3f", Double(row.playbackBytes) / Double(assetBytes))
        } else {
            pct = "unknown"
        }
        print(
            """
            [ClipAVPlayerEgress] clipID=\(clipID) assetBytes=\(asset) \
            playerInstances=\(row.playerInstances) itemInstances=\(row.itemInstances) \
            playbackRequests=\(row.playbackRequests) playbackBytes=\(row.playbackBytes) \
            playbackPercentOfAsset=\(pct) prefetchBytes=\(row.prefetchBytes) \
            activeBytes=\(row.activeBytes) loops=\(row.loops) recreations=\(row.recreations)
            """
        )
    }

    nonisolated static func logPrefetchEgress(clipID: String, becameActive: Bool) {
        lock.lock()
        let row = byClipID[clipID] ?? ClipEgress()
        lock.unlock()
        let asset = row.assetBytes.map(String.init) ?? "unknown"
        let observed = becameActive ? row.playbackBytes : row.prefetchBytes
        let pct: String
        if let assetBytes = row.assetBytes, assetBytes > 0 {
            pct = String(format: "%.3f", Double(observed) / Double(assetBytes))
        } else {
            pct = "unknown"
        }
        print(
            """
            [ClipPrefetchEgress] clipID=\(clipID) assetBytes=\(asset) \
            observedBytes=\(observed) observedPercent=\(pct) becameActive=\(becameActive)
            """
        )
    }

    nonisolated static func logExperienceSummary(context: String) {
        lock.lock()
        let snapshot = byClipID
        lock.unlock()
        var playerInstancesCreated = 0
        var itemsCreated = 0
        var playbackNetworkBytes: Int64 = 0
        var prefetchNetworkBytes: Int64 = 0
        var activeNetworkBytes: Int64 = 0
        var clipsOver50 = 0
        var clipsOver90 = 0
        for (_, row) in snapshot {
            playerInstancesCreated += row.playerInstances
            itemsCreated += row.itemInstances
            playbackNetworkBytes += row.playbackBytes
            prefetchNetworkBytes += row.prefetchBytes
            activeNetworkBytes += row.activeBytes
            if let asset = row.assetBytes, asset > 0 {
                let fraction = Double(row.playbackBytes) / Double(asset)
                if fraction >= 0.5 { clipsOver50 += 1 }
                if fraction >= 0.9 { clipsOver90 += 1 }
            }
        }
        print(
            """
            [ClipAVPlayerEgressSummary] context=\(context) uniqueClips=\(snapshot.count) \
            playerInstancesCreated=\(playerInstancesCreated) itemsCreated=\(itemsCreated) \
            playbackNetworkBytes=\(playbackNetworkBytes) prefetchNetworkBytes=\(prefetchNetworkBytes) \
            activeNetworkBytes=\(activeNetworkBytes) avoidableRecreationBytes=unknown \
            clipsOver50PercentOnFirstView=\(clipsOver50) clipsOver90PercentOnFirstView=\(clipsOver90)
            """
        )
    }
}
#else
nonisolated enum ClipAVPlayerEgressTelemetry {
    nonisolated static func resetSession() {}
    nonisolated static func noteKnownAssetBytes(clipID: String, bytes: Int64) {}
    nonisolated static func recordPlaybackDelta(clipID: String, role: String, deltaBytes: Int64, sessionItemBytes: Int64) {}
    nonisolated static func logClipSummary(clipID: String) {}
    nonisolated static func logPrefetchEgress(clipID: String, becameActive: Bool) {}
    nonisolated static func logExperienceSummary(context: String) {}
}
#endif
