import CoreGraphics
import Foundation
import LiveKit

/// Secondary renderer that signals when subscribed program video emits its first non-empty frame.
@MainActor
final class BroadcastProgramVideoFirstFrameObserver: NSObject, VideoRenderer {
    var onFirstFrame: (() -> Void)?
    private var didFire = false

    var isAdaptiveStreamEnabled: Bool { false }

    var adaptiveStreamSize: CGSize { .zero }

    func reset() {
        didFire = false
    }

    nonisolated func render(frame: VideoFrame) {
        guard frame.dimensions.width > 0, frame.dimensions.height > 0 else { return }
        Task { @MainActor in
            guard !didFire else { return }
            didFire = true
            onFirstFrame?()
        }
    }
}