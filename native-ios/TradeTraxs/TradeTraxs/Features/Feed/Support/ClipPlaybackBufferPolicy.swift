import AVFoundation
import Foundation

/// Path qualities that change short-form clip download behavior.
nonisolated struct ClipPlaybackNetworkPosture: Equatable, Sendable {
    var isOnline: Bool
    var isExpensive: Bool
    var isConstrained: Bool
    var usesCellular: Bool

    /// `wifi`, `cellular`, `constrained`, `expensive`, or `offline`.
    var networkClass: String {
        if !isOnline { return "offline" }
        if isConstrained { return "constrained" }
        if usesCellular { return "cellular" }
        if isExpensive { return "expensive" }
        return "wifi"
    }

    /// Low Data Mode, cellular, or any expensive path. Unconstrained Wi-Fi stays unrestricted.
    var shouldConserveVideoBandwidth: Bool {
        !isOnline || isConstrained || isExpensive || usesCellular
    }

    static let wifi = ClipPlaybackNetworkPosture(
        isOnline: true,
        isExpensive: false,
        isConstrained: false,
        usesCellular: false
    )

    static let cellular = ClipPlaybackNetworkPosture(
        isOnline: true,
        isExpensive: true,
        isConstrained: false,
        usesCellular: true
    )
}

nonisolated protocol ClipPlaybackNetworkPostureProviding: Sendable {
    func currentPosture() -> ClipPlaybackNetworkPosture
}

nonisolated struct ClipPlaybackLiveNetworkPosture: ClipPlaybackNetworkPostureProviding {
    func currentPosture() -> ClipPlaybackNetworkPosture {
        let qualities = ReachabilityPathQualityStore.snapshot()
        return ClipPlaybackNetworkPosture(
            isOnline: qualities.isOnline,
            isExpensive: qualities.isExpensive,
            isConstrained: qualities.isConstrained,
            usesCellular: qualities.usesCellular
        )
    }
}

nonisolated final class ClipPlaybackFixedNetworkPosture: ClipPlaybackNetworkPostureProviding, @unchecked Sendable {
    var posture: ClipPlaybackNetworkPosture

    init(posture: ClipPlaybackNetworkPosture) {
        self.posture = posture
    }

    func currentPosture() -> ClipPlaybackNetworkPosture { posture }
}

/// Short-form progressive MP4 buffer policy.
///
/// `preferredForwardBufferDuration` is only a hint. A progressive file has no segment boundary,
/// so AVFoundation can still read ahead of this window. Zero is not a small buffer: it means
/// "player chooses" and is the aggressive default.
///
/// `automaticallyWaitsToMinimizeStalling` stays false. When it is true, AVPlayer buffers toward
/// a stall-free play of the whole item. On a fast path that pulled tens of megabytes of a
/// ~53 MB file during the first ~1.3 seconds of playback.
nonisolated struct ClipPlaybackBufferConfiguration: Equatable, Sendable {
    var activeForwardBufferSeconds: TimeInterval
    var prefetchForwardBufferSeconds: TimeInterval
    var allowsNeighborPrefetch: Bool
    var waitsToMinimizeStalling: Bool
    var networkClass: String

    static func make(for posture: ClipPlaybackNetworkPosture) -> ClipPlaybackBufferConfiguration {
        if posture.shouldConserveVideoBandwidth {
            return ClipPlaybackBufferConfiguration(
                activeForwardBufferSeconds: 1,
                prefetchForwardBufferSeconds: 1,
                allowsNeighborPrefetch: false,
                waitsToMinimizeStalling: false,
                networkClass: posture.networkClass
            )
        }
        return ClipPlaybackBufferConfiguration(
            activeForwardBufferSeconds: 2,
            prefetchForwardBufferSeconds: 1,
            allowsNeighborPrefetch: true,
            waitsToMinimizeStalling: false,
            networkClass: posture.networkClass
        )
    }

    static func allowsPersistentFullFileFill(
        posture: ClipPlaybackNetworkPosture = ClipPlaybackLiveNetworkPosture().currentPosture()
    ) -> Bool {
        !posture.shouldConserveVideoBandwidth
    }
}

nonisolated enum ClipPlaybackTransferMetrics {
    static func bytesPerPlaybackSecond(bytesTransferred: Int64, playbackSeconds: Double) -> Double? {
        guard bytesTransferred >= 0, playbackSeconds >= 0.05 else { return nil }
        return Double(bytesTransferred) / playbackSeconds
    }

    static func assetFraction(bytesTransferred: Int64, assetBytes: Int64?) -> Double? {
        guard let assetBytes, assetBytes > 0, bytesTransferred >= 0 else { return nil }
        return Double(bytesTransferred) / Double(assetBytes)
    }
}

nonisolated enum ClipPlaybackBufferInspection {
    static func bufferedAheadSeconds(item: AVPlayerItem) -> Double? {
        let current = item.currentTime().seconds
        guard current.isFinite else { return nil }
        let ends = item.loadedTimeRanges.compactMap { value -> Double? in
            let end = CMTimeRangeGetEnd(value.timeRangeValue).seconds
            guard end.isFinite else { return nil }
            return end
        }
        guard let end = ends.max() else { return nil }
        return max(0, end - current)
    }

    static func playbackSeconds(item: AVPlayerItem) -> Double {
        guard let events = item.accessLog()?.events, !events.isEmpty else { return 0 }
        return events.reduce(0) { partial, event in
            let watched = event.durationWatched
            guard watched.isFinite, watched > 0 else { return partial }
            return partial + watched
        }
    }
}

/// Builds a short-form player with the buffer hint applied before AVPlayer starts loading.
enum ClipShortFormPlayerFactory {
    nonisolated static func makePlayer(
        url: URL,
        forwardBufferSeconds: TimeInterval
    ) -> (item: AVPlayerItem, player: AVPlayer) {
        let item = AVPlayerItem(url: url)
        applyBufferHint(to: item, forwardBufferSeconds: forwardBufferSeconds)
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = false
        return (item, player)
    }

    nonisolated static func applyBufferHint(to item: AVPlayerItem, forwardBufferSeconds: TimeInterval) {
        item.preferredForwardBufferDuration = max(forwardBufferSeconds, 1)
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = false
    }

    /// Stops asset and media loading. Call only after observers registered on this player are removed.
    static func stopNetworkLoading(_ player: AVPlayer) {
        if let item = player.currentItem {
            item.asset.cancelLoading()
        }
        player.replaceCurrentItem(with: nil)
    }
}
