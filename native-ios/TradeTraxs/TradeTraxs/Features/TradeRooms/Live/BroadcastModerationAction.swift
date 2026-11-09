import Foundation

/// Mirrors web `BroadcastModerationClientAction` / POST `/api/livekit/broadcast/moderate`.
enum BroadcastModerationAction: String, Sendable {
    case inviteSpeak = "invite_speak"
    case requestUnmute = "request_unmute"
    case muteSpeaker = "mute_speaker"
    case revokeSpeaker = "revoke_speaker"
    case removeViewer = "remove_viewer"
    case dismissHand = "dismiss_hand"
}
