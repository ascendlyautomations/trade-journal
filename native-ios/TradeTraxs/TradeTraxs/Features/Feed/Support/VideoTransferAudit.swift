import AVFoundation
import Foundation

#if DEBUG
/// Temporary physical-device audit — proves whether access-log bytes reflect real network transfer.
enum VideoTransferAudit {
    static func logPlayerCreated(
        clipID: String,
        surface: String,
        role: String,
        player: AVPlayer,
        item: AVPlayerItem,
        preferredForwardBufferDuration: TimeInterval,
        canUseNetworkWhilePaused: Bool
    ) {
        print(
            """
            [VideoTransferAudit] \
            clipID=\(clipID) \
            surface=\(surface) \
            role=\(role) \
            phase=playerCreated \
            playerInstanceID=\(ObjectIdentifier(player)) \
            itemInstanceID=\(ObjectIdentifier(item)) \
            preferredForwardBufferDuration=\(preferredForwardBufferDuration) \
            networkWhilePaused=\(canUseNetworkWhilePaused) \
            canUseNetworkResourcesForLiveStreamingWhilePaused=\(canUseNetworkWhilePaused) \
            automaticallyWaitsToMinimizeStalling=\(player.automaticallyWaitsToMinimizeStalling) \
            reason=playerCreated
            """
        )
    }

    static func logAccessLogEvent(
        clipID: String,
        surface: String,
        role: String,
        item: AVPlayerItem,
        accounting: VideoAccessLogAccounting.DeltaResult,
        reason: String
    ) {
        guard let event = item.accessLog()?.events.last else { return }

        let playbackSeconds: String
        if event.durationWatched.isFinite, event.durationWatched >= 0 {
            playbackSeconds = String(format: "%.3f", event.durationWatched)
        } else {
            playbackSeconds = "unknown"
        }

        let observedBitrate: String
        if event.observedBitrate.isFinite, event.observedBitrate > 0 {
            observedBitrate = String(format: "%.0f", event.observedBitrate)
        } else {
            observedBitrate = "unknown"
        }

        let indicatedBitrate: String
        if event.indicatedBitrate.isFinite, event.indicatedBitrate > 0 {
            indicatedBitrate = String(format: "%.0f", event.indicatedBitrate)
        } else {
            indicatedBitrate = "unknown"
        }

        print(
            """
            [VideoTransferAudit] \
            clipID=\(clipID) \
            surface=\(surface) \
            role=\(role) \
            playerInstanceID=\(accounting.playerInstanceID ?? "nil") \
            itemInstanceID=\(accounting.itemInstanceID) \
            accessLogEventIndex=\(accounting.eventIndex) \
            accessLogEventCount=\(accounting.accessLogEventCount) \
            eventBytes=\(accounting.eventBytes) \
            previousEventBytes=\(accounting.previousEventBytes) \
            newBytes=\(accounting.newBytes) \
            trueDeltaBytes=\(accounting.newBytes) \
            sessionItemBytes=\(accounting.sessionItemBytes) \
            sessionVideoBytes=\(accounting.sessionVideoBytes) \
            numberOfMediaRequests=\(event.numberOfMediaRequests) \
            observedBitrate=\(observedBitrate) \
            indicatedBitrate=\(indicatedBitrate) \
            playbackSeconds=\(playbackSeconds) \
            transferDuration=\(String(format: "%.3f", event.transferDuration)) \
            preferredForwardBufferDuration=\(item.preferredForwardBufferDuration) \
            networkWhilePaused=\(item.canUseNetworkResourcesForLiveStreamingWhilePaused) \
            automaticallyWaitsToMinimizeStalling=true \
            uriHost=\(event.uri.flatMap { URL(string: $0)?.host } ?? "unknown") \
            reason=\(reason)
            """
        )
    }
}
#else
enum VideoTransferAudit {
    static func logPlayerCreated(
        clipID: String,
        surface: String,
        role: String,
        player: AVPlayer,
        item: AVPlayerItem,
        preferredForwardBufferDuration: TimeInterval,
        canUseNetworkWhilePaused: Bool
    ) {}

    static func logAccessLogEvent(
        clipID: String,
        surface: String,
        role: String,
        item: AVPlayerItem,
        accounting: VideoAccessLogAccounting.DeltaResult,
        reason: String
    ) {}
}
#endif
