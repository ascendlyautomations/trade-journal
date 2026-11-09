import Foundation
import LiveKit

/// OBS ingress program video selection — mirrors web `findObsProgramVideoPublication`.
enum BroadcastObsProgramVideo {
    static let ingressIdentityPrefix = "tt-obs-"

    static func programPublisherIdentity(forSessionId sessionId: String) -> String {
        "\(ingressIdentityPrefix)\(sessionId.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    static func isObsSession(broadcastSource: String?, videoSource: String?) -> Bool {
        if broadcastSource?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "obs" {
            return true
        }
        if videoSource?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "obs" {
            return true
        }
        return false
    }

    static func resolvedProgramPublisherIdentity(
        sessionId: String,
        primaryFromToken: String?,
        primaryFromStatus: String?
    ) -> String {
        let fromToken = primaryFromToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !fromToken.isEmpty { return fromToken }
        let fromStatus = primaryFromStatus?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !fromStatus.isEmpty { return fromStatus }
        return programPublisherIdentity(forSessionId: sessionId)
    }

    static func isScreenShareVideoSource(_ source: Track.Source) -> Bool {
        BroadcastProgramVideoSources.isScreenShare(source)
    }

    static func isCameraVideoSource(_ source: Track.Source) -> Bool {
        BroadcastProgramVideoSources.isCamera(source)
    }

    /// Prefer screen-share, then any non-camera, then camera (ingress may publish a blank camera + program).
    static func pickProgramVideoTrack(
        programPublisherIdentity: String?,
        from room: Room
    ) -> VideoTrack? {
        let programId = programPublisherIdentity?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let programId, !programId.isEmpty,
              let participant = room.remoteParticipants.values.first(where: {
                  $0.identity?.stringValue == programId
              })
        else {
            return nil
        }

        var screenCandidate: (track: VideoTrack, source: Track.Source, sid: Track.Sid?)?
        var nonCameraCandidate: (track: VideoTrack, source: Track.Source, sid: Track.Sid?)?
        var cameraCandidate: (track: VideoTrack, source: Track.Source, sid: Track.Sid?)?

        for pub in participant.trackPublications.values {
            guard pub.kind == .video, let track = pub.track as? VideoTrack else { continue }
            let sid = pub.sid
            if isScreenShareVideoSource(pub.source) {
                screenCandidate = (track, pub.source, sid)
                break
            }
            if isCameraVideoSource(pub.source) {
                if cameraCandidate == nil {
                    cameraCandidate = (track, pub.source, sid)
                }
            } else if nonCameraCandidate == nil {
                nonCameraCandidate = (track, pub.source, sid)
            }
        }

        let chosen = screenCandidate ?? nonCameraCandidate ?? cameraCandidate
        if let chosen {
            #if DEBUG
            print(
                """
                [TradeTraxs Broadcast] OBS program video selected \
                participant=\(programId) source=\(chosen.source) sid=\(chosen.sid?.stringValue ?? "nil")
                """
            )
            #endif
            return chosen.track
        }
        #if DEBUG
        print("[TradeTraxs Broadcast] OBS program video none subscribed participant=\(programId)")
        #endif
        return nil
    }
}
