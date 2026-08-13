import AVKit
import SwiftUI
import UIKit

/// Native ``AVPlayerViewController`` — play/pause, scrubbing, fullscreen.
/// Optional double-tap Like uses a non-cancelling recognizer so controls keep working.
struct ClipPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    var onDoubleTapLike: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        controller.videoGravity = .resizeAspect
        context.coordinator.attachDoubleTap(to: controller)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
        context.coordinator.onDoubleTapLike = onDoubleTapLike
        context.coordinator.attachDoubleTap(to: controller)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDoubleTapLike: onDoubleTapLike)
    }

    final class Coordinator: NSObject {
        var onDoubleTapLike: (() -> Void)?
        private weak var attachedView: UIView?
        private var recognizer: UITapGestureRecognizer?

        init(onDoubleTapLike: (() -> Void)?) {
            self.onDoubleTapLike = onDoubleTapLike
        }

        func attachDoubleTap(to controller: AVPlayerViewController) {
            guard onDoubleTapLike != nil else {
                if let recognizer {
                    attachedView?.removeGestureRecognizer(recognizer)
                    self.recognizer = nil
                    attachedView = nil
                }
                return
            }
            guard attachedView !== controller.view else { return }
            if let recognizer {
                attachedView?.removeGestureRecognizer(recognizer)
            }
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
            tap.numberOfTapsRequired = 2
            tap.cancelsTouchesInView = false
            controller.view.addGestureRecognizer(tap)
            recognizer = tap
            attachedView = controller.view
        }

        @objc private func handleDoubleTap() {
            onDoubleTapLike?()
        }
    }
}
