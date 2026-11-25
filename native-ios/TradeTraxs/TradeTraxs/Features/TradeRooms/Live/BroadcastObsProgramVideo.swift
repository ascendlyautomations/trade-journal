import Foundation
import LiveKit

/// OBS ingress program video selection, mirrors web `findObsProgramVideoPublication`.
enum BroadcastObsProgramVideo {
    static let ingressIdentityPrefix = "tt-obs-"

    /// True for the OBS ingress LiveKit participant (not a TradeTraxs user).
    static func isIngressPublisherIdentity(
        _ identity: String,
        programPublisherIdentity: String? = nil
    ) -> Bool {
        let trimmed = identity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix(ingressIdentityPrefix) { return true }
        let program = programPublisherIdentity?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !program.isEmpty, trimmed == program { return true }
        return false
    }

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
    ) -> (track: VideoTrack, publicationSid: String?)? {
        let programId = programPublisherIdentity?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let programId, !programId.isEmpty,
              let participant = room.remoteParticipants.values.first(where: {
                  $0.identity?.stringValue == programId
              })
        else {
            return nil
        }

        typealias VideoCandidate = (track: VideoTrack, source: Track.Source, sid: Track.Sid?)

        var screenCandidate: VideoCandidate?
        var nonCameraCandidate: VideoCandidate?
        var cameraCandidate: VideoCandidate?

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
            return (chosen.track, chosen.sid?.stringValue)
        }
        #if DEBUG
        print("[TradeTraxs Broadcast] OBS program video none subscribed participant=\(programId)")
        #endif
        return nil
    }

    /// Legacy convenience — prefer the tuple overload for publication-stable apply.
    static func pickProgramVideoTrackOnly(
        programPublisherIdentity: String?,
        from room: Room
    ) -> VideoTrack? {
        pickProgramVideoTrack(programPublisherIdentity: programPublisherIdentity, from: room)?.track
    }
}
