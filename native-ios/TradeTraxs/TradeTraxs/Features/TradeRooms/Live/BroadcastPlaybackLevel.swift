import Foundation

/// Livestream playback gain. Hardware output volume stays on the system volume buttons.
enum BroadcastPlaybackLevel {
    enum SubscribeKind {
        case audio
        case video
        case other
    }

    static func clampedGain(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    /// Mute outputs silence and keeps `gain` for the next unmute.
    static func trackVolume(muted: Bool, gain: Double) -> Double {
        muted ? 0 : clampedGain(gain)
    }

    /// Audio subscriptions must inherit the current level. Video subscriptions still refresh it.
    static func shouldApplyPlayback(on kind: SubscribeKind) -> Bool {
        kind == .audio || kind == .video
    }
}
