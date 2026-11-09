import Foundation

nonisolated struct LiveKitBroadcastInteractiveStateResponse: Decodable, Sendable {
    var snapshot: Snapshot?
    var profiles: [ProfileLite]?
    var error: String?

    nonisolated struct Snapshot: Decodable, Sendable {
        var sessionId: String?
        var roomId: String?
        var broadcasterUserId: String?
        var broadcastSource: String?
        var primaryMediaPublisherIdentity: String?
        var livekitIngressId: String?
        var ingressStatusSnapshot: String?
        var voiceMode: String?
        var speakerGrants: [String]?
        var sessionBlocks: [String]?
        var pendingInvitations: [HostPendingInvitation]?
        var raisedHands: [RaisedHand]?
        var removedFromStream: Bool?
        /// True when the viewer is blocked from rejoining this broadcast session (moderation).
        var blockedFromBroadcastRejoin: Bool?
        /// True when this user currently appears as a LiveKit participant in the broadcast room.
        var presentInLiveKitBroadcastRoom: Bool?
        var pendingInvitationForViewer: ViewerPendingInvitation?

        nonisolated struct HostPendingInvitation: Decodable, Sendable {
            var userId: String
            var invitationId: String
        }

        nonisolated struct RaisedHand: Decodable, Sendable {
            var userId: String
            var raisedAt: String?
        }

        nonisolated struct ViewerPendingInvitation: Decodable, Sendable {
            var invitationId: String
        }
    }

    nonisolated struct ProfileLite: Decodable, Sendable {
        var userId: String
        var username: String?
        var displayName: String?
        var avatarUrl: String?
    }
}

nonisolated struct LiveKitBroadcastModerationResponse: Decodable, Sendable {
    var ok: Bool?
    var error: String?
    var retryable: Bool?
    var invitationId: String?
    var targetDisplayName: String?
}

nonisolated struct LiveKitBroadcastInviteRespondResponse: Decodable, Sendable {
    var ok: Bool?
    var declined: Bool?
    var error: String?
    var token: String?
    var livekitUrl: String?
    var broadcastSessionId: String?
    var roomId: String?
    var broadcasterUserId: String?
    var broadcasterDisplayName: String?
    var startedAt: String?
    var voiceMode: String?
    var videoSource: String?
    var broadcastSource: String?
    var primaryMediaPublisherIdentity: String?
    var canPublish: Bool?
    var role: String?
}
