import Foundation
import LiveKit

/// Shared LiveKit video source classification for browser + OBS program selection.
enum BroadcastProgramVideoSources {
    static func isScreenShare(_ source: Track.Source) -> Bool {
        source == .screenShareVideo
    }

    static func isCamera(_ source: Track.Source) -> Bool {
        source == .camera
    }
}
