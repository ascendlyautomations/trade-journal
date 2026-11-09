import Foundation
import LiveKit

/// Browser host program feed — mirrors web `findBrowserBroadcasterProgramVideoPublication`.
enum BroadcastBrowserProgramVideo {
    struct PublicationChoice: Equatable {
        var source: Track.Source
        var publicationSid: String?
    }

    /// Pick screen over camera when both have subscribed tracks (mid-stream share).
    static func pickProgramVideoPublicationSnapshots(
        _ snapshots: [PublicationChoice]
    ) -> PublicationChoice? {
        var camera: PublicationChoice?
        for snap in snapshots where snap.publicationSid != nil {
            if BroadcastProgramVideoSources.isScreenShare(snap.source) {
                return snap
            }
            if BroadcastProgramVideoSources.isCamera(snap.source), camera == nil {
                camera = snap
            }
        }
        return camera
    }

    static func pickProgramVideoTrack(
        broadcasterIdentity: String,
        from room: Room
    ) -> (track: VideoTrack, publicationSid: String?)? {
        guard let participant = room.remoteParticipants.values.first(where: {
            $0.identity?.stringValue == broadcasterIdentity
        }) else {
            return nil
        }

        var screenPublication: TrackPublication?
        var cameraPublication: TrackPublication?

        for pub in participant.trackPublications.values {
            guard pub.kind == .video, pub.track is VideoTrack else { continue }
            if BroadcastProgramVideoSources.isScreenShare(pub.source) {
                screenPublication = pub
                break
            }
            if BroadcastProgramVideoSources.isCamera(pub.source), cameraPublication == nil {
                cameraPublication = pub
            }
        }

        let chosen = screenPublication ?? cameraPublication
        guard let chosen, let track = chosen.track as? VideoTrack else {
            #if DEBUG
            print(
                """
                [TradeTraxs Broadcast] browser program video none \
                host=\(broadcasterIdentity) videoPubs=\(participant.trackPublications.count)
                """
            )
            #endif
            return nil
        }

        #if DEBUG
        print(
            """
            [TradeTraxs Broadcast] browser program video selected \
            host=\(broadcasterIdentity) source=\(chosen.source) \
            pubSid=\(chosen.sid.stringValue) trackSid=\(track.sid?.stringValue ?? "nil")
            """
        )
        #endif
        return (track, chosen.sid.stringValue)
    }
}
