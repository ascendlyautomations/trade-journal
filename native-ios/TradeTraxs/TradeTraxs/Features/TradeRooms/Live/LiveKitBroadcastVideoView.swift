import LiveKit
import SwiftUI

struct LiveKitBroadcastVideoView: UIViewRepresentable {
    var track: VideoTrack?
    var onFirstFrame: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onFirstFrame: onFirstFrame)
    }

    func makeUIView(context: Context) -> VideoView {
        let view = VideoView()
        view.layoutMode = .fit
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: VideoView, context: Context) {
        context.coordinator.onFirstFrame = onFirstFrame
        context.coordinator.bindFrameObserver(to: track)
        uiView.track = track
    }

    final class Coordinator {
        var onFirstFrame: (() -> Void)?
        private let frameObserver = BroadcastProgramVideoFirstFrameObserver()
        private weak var observedTrack: VideoTrack?

        init(onFirstFrame: (() -> Void)?) {
            self.onFirstFrame = onFirstFrame
            frameObserver.onFirstFrame = { [weak self] in
                self?.onFirstFrame?()
            }
        }

        func bindFrameObserver(to track: VideoTrack?) {
            if let observedTrack, observedTrack !== track {
                observedTrack.remove(videoRenderer: frameObserver)
                self.observedTrack = nil
            }
            guard let track, track !== observedTrack else { return }
            frameObserver.reset()
            track.add(videoRenderer: frameObserver)
            observedTrack = track
        }

        deinit {
            if let observedTrack {
                observedTrack.remove(videoRenderer: frameObserver)
            }
        }
    }
}
