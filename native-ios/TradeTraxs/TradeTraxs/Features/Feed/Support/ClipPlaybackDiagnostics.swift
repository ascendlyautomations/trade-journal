import AVFoundation
import Foundation

#if DEBUG
enum ClipBandwidthLogger {
    enum Event: String {
        case playerCreated
        case play
        case pause
        case playerReleased
        case accessLog
    }

    static func log(
        clipID: String,
        event: Event,
        urlIdentity: String? = nil,
        isVisible: Bool? = nil,
        isCurrentPage: Bool? = nil
    ) {
        var parts = [
            "[ClipBandwidth]",
            "clipID=\(clipID)",
            "event=\(event.rawValue)",
        ]
        if let urlIdentity, !urlIdentity.isEmpty {
            parts.append("urlIdentity=\(urlIdentity)")
        }
        if let isVisible {
            parts.append("isVisible=\(isVisible)")
        }
        if let isCurrentPage {
            parts.append("isCurrentPage=\(isCurrentPage)")
        }
        print(parts.joined(separator: " "))
    }

    static func logAccessLog(
        clipID: String,
        cumulativeBytes: Int64,
        deltaBytes: Int64,
        mediaRequests: Int,
        transferDuration: TimeInterval,
        observedBitrate: Double
    ) {
        print(
            """
            [ClipBandwidth] clipID=\(clipID) event=accessLog \
            cumulativeBytesTransferred=\(cumulativeBytes) \
            deltaBytesTransferred=\(deltaBytes) \
            mediaRequests=\(mediaRequests) \
            transferDuration=\(String(format: "%.3f", transferDuration)) \
            observedBitrate=\(String(format: "%.0f", observedBitrate))
            """
        )
    }

    static func logTransferSnapshot(
        clipID: String,
        event: String,
        role: String,
        lifecycle: String,
        assetBytes: Int64?,
        bytesTransferred: Int64,
        rawBytesTransferred: Int64,
        playbackSeconds: Double,
        networkClass: String,
        startReason: String?,
        stopReason: String?,
        forwardBufferSeconds: TimeInterval,
        waitsToMinimizeStalling: Bool,
        bufferedAheadSeconds: Double?,
        mediaRequests: Int?,
        indicatedBitrate: Double?,
        observedBitrate: Double?,
        preferredPeakBitRate: Double?,
        preferredMaximumResolution: String,
        playWallSeconds: Double?
    ) {
        let bytesPerPlaybackSecond = ClipPlaybackTransferMetrics.bytesPerPlaybackSecond(
            bytesTransferred: bytesTransferred,
            playbackSeconds: playbackSeconds
        )
        let assetFraction = ClipPlaybackTransferMetrics.assetFraction(
            bytesTransferred: bytesTransferred,
            assetBytes: assetBytes
        )
        print(
            """
            [ClipBandwidth] clipID=\(clipID) event=\(event) role=\(role) lifecycle=\(lifecycle) \
            assetBytes=\(Self.intText(assetBytes)) bytesTransferred=\(bytesTransferred) \
            rawBytesTransferred=\(rawBytesTransferred) playbackSeconds=\(Self.secondsText(playbackSeconds)) \
            playWallSeconds=\(Self.optionalSecondsText(playWallSeconds)) \
            bytesPerPlaybackSecond=\(Self.optionalSecondsText(bytesPerPlaybackSecond)) \
            assetFraction=\(Self.optionalSecondsText(assetFraction)) \
            networkClass=\(networkClass) startReason=\(startReason ?? "none") \
            stopReason=\(stopReason ?? "none") forwardBufferSeconds=\(Self.secondsText(forwardBufferSeconds)) \
            waitsToMinimizeStalling=\(waitsToMinimizeStalling) \
            bufferedAheadSeconds=\(Self.optionalSecondsText(bufferedAheadSeconds)) \
            mediaRequests=\(mediaRequests.map(String.init) ?? "none") \
            indicatedBitrate=\(Self.optionalBitrateText(indicatedBitrate)) \
            observedBitrate=\(Self.optionalBitrateText(observedBitrate)) \
            preferredPeakBitRate=\(Self.optionalBitrateText(preferredPeakBitRate)) \
            preferredMaximumResolution=\(preferredMaximumResolution)
            """
        )
    }

    private static func intText(_ value: Int64?) -> String {
        value.map(String.init) ?? "unknown"
    }

    private static func secondsText(_ value: Double) -> String {
        guard value.isFinite else { return "unknown" }
        return String(format: "%.3f", value)
    }

    private static func optionalSecondsText(_ value: Double?) -> String {
        guard let value else { return "unknown" }
        return secondsText(value)
    }

    private static func optionalBitrateText(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "unknown" }
        if value <= 0 { return "0" }
        return String(format: "%.0f", value)
    }
}

enum ClipPlaybackLogger {
    static func log(
        activeClip: String?,
        retainedPlayers: Int,
        visibleClips: Int
    ) {
        print(
            """
            [ClipPlayback] activeClip=\(activeClip ?? "nil") \
            retainedPlayers=\(retainedPlayers) \
            visibleClips=\(visibleClips)
            """
        )
    }
}
#else
enum ClipBandwidthLogger {
    enum Event: String {
        case playerCreated, play, pause, playerReleased, accessLog
    }

    static func log(
        clipID: String,
        event: Event,
        urlIdentity: String? = nil,
        isVisible: Bool? = nil,
        isCurrentPage: Bool? = nil
    ) {}

    static func logAccessLog(
        clipID: String,
        cumulativeBytes: Int64,
        deltaBytes: Int64,
        mediaRequests: Int,
        transferDuration: TimeInterval,
        observedBitrate: Double
    ) {}

    static func logTransferSnapshot(
        clipID: String,
        event: String,
        role: String,
        lifecycle: String,
        assetBytes: Int64?,
        bytesTransferred: Int64,
        rawBytesTransferred: Int64,
        playbackSeconds: Double,
        networkClass: String,
        startReason: String?,
        stopReason: String?,
        forwardBufferSeconds: TimeInterval,
        waitsToMinimizeStalling: Bool,
        bufferedAheadSeconds: Double?,
        mediaRequests: Int?,
        indicatedBitrate: Double?,
        observedBitrate: Double?,
        preferredPeakBitRate: Double?,
        preferredMaximumResolution: String,
        playWallSeconds: Double?
    ) {}
}

enum ClipPlaybackLogger {
    static func log(activeClip: String?, retainedPlayers: Int, visibleClips: Int) {}
}
#endif

extension Reel {
    var playbackURLIdentity: String {
        let raw = video.id.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: raw), let host = url.host {
            return host + url.path
        }
        return raw
    }
}
