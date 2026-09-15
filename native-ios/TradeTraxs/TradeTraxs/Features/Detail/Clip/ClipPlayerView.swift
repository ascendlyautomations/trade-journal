import AVFoundation
import AVKit
import SwiftUI
import UIKit

/// Native ``AVPlayerViewController`` — play/pause, scrubbing, fullscreen.
/// Optional double-tap Like uses a non-cancelling recognizer so controls keep working.
struct ClipPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspect
    var onDoubleTapLike: (() -> Void)? = nil
    var onReadyForDisplayChange: ((Bool) -> Void)? = nil

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        controller.videoGravity = videoGravity
        controller.view.backgroundColor = .clear
        context.coordinator.onReadyForDisplayChange = onReadyForDisplayChange
        context.coordinator.attachDoubleTap(to: controller)
        context.coordinator.observeReadyForDisplay(in: controller)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
        if controller.videoGravity != videoGravity {
            controller.videoGravity = videoGravity
        }
        context.coordinator.onDoubleTapLike = onDoubleTapLike
        context.coordinator.onReadyForDisplayChange = onReadyForDisplayChange
        context.coordinator.attachDoubleTap(to: controller)
        context.coordinator.observeReadyForDisplay(in: controller)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDoubleTapLike: onDoubleTapLike, onReadyForDisplayChange: onReadyForDisplayChange)
    }

    final class Coordinator: NSObject {
        var onDoubleTapLike: (() -> Void)?
        var onReadyForDisplayChange: ((Bool) -> Void)?
        private weak var attachedView: UIView?
        private var recognizer: UITapGestureRecognizer?
        private var readyForDisplayObservation: NSKeyValueObservation?

        init(onDoubleTapLike: (() -> Void)?, onReadyForDisplayChange: ((Bool) -> Void)?) {
            self.onDoubleTapLike = onDoubleTapLike
            self.onReadyForDisplayChange = onReadyForDisplayChange
        }

        func observeReadyForDisplay(in controller: AVPlayerViewController) {
            readyForDisplayObservation?.invalidate()
            guard let layer = Self.findPlayerLayer(in: controller.view) else { return }
            readyForDisplayObservation = layer.observe(\.isReadyForDisplay, options: [.initial, .new]) {
                [weak self] layer, _ in
                let ready = layer.isReadyForDisplay
                DispatchQueue.main.async {
                    self?.onReadyForDisplayChange?(ready)
                }
            }
        }

        private static func findPlayerLayer(in view: UIView) -> AVPlayerLayer? {
            if let playerLayer = view.layer as? AVPlayerLayer {
                return playerLayer
            }
            for subview in view.subviews {
                if let found = findPlayerLayer(in: subview) {
                    return found
                }
            }
            if let sublayers = view.layer.sublayers {
                for layer in sublayers {
                    if let playerLayer = layer as? AVPlayerLayer {
                        return playerLayer
                    }
                }
            }
            return nil
        }

        deinit {
            readyForDisplayObservation?.invalidate()
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
