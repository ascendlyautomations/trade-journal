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
