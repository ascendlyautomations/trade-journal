import AVFoundation
import Foundation

/// Central, idempotent AVAudioSession setup for Feed inline / Clips pager playback.
enum FeedVideoAudioSession {
    private static var isPlaybackConfigured = false

    static func activateForPlaybackIfNeeded() {
        guard !isPlaybackConfigured else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
            isPlaybackConfigured = true
        } catch {
#if DEBUG
            print("[FeedVideoAudio] session activation failed: \(error.localizedDescription)")
#endif
        }
    }

    static func applyMute(_ muted: Bool, to player: AVPlayer) {
        activateForPlaybackIfNeeded()
        player.isMuted = muted
        player.volume = muted ? 0 : 1.0
    }
}
