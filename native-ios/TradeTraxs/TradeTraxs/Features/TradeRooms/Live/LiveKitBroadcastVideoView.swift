import LiveKit
import SwiftUI
import UIKit

struct LiveKitBroadcastVideoView: UIViewRepresentable {
    var track: VideoTrack?
    var trackRevision: UInt = 0
    var onFirstFrame: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> BroadcastInlineVideoHostView {
        let host = BroadcastInlineVideoHostView()
        context.coordinator.hostView = host
        return host
    }

    func updateUIView(_ uiView: BroadcastInlineVideoHostView, context: Context) {
        context.coordinator.hostView = uiView
        context.coordinator.track = track
        context.coordinator.trackRevision = trackRevision
        context.coordinator.attachment.onFirstFrame = onFirstFrame
        uiView.onDidLayoutVideoView = { [weak coordinator = context.coordinator] in
            coordinator?.reapplyTrackIfNeeded()
        }
        context.coordinator.applyTrack()
    }

    static func dismantleUIView(_ uiView: BroadcastInlineVideoHostView, coordinator: Coordinator) {
        coordinator.attachment.detach()
        uiView.videoView.track = nil
        uiView.onDidLayoutVideoView = nil
    }

    @MainActor
    final class Coordinator {
        weak var hostView: BroadcastInlineVideoHostView?
        var track: VideoTrack?
        var trackRevision: UInt = 0
        let attachment = BroadcastProgramVideoViewAttachment()

        func applyTrack() {
            guard let hostView else { return }
            attachment.apply(incomingTrack: track, revision: trackRevision, to: hostView.videoView)
        }

        func reapplyTrackIfNeeded() {
            applyTrack()
        }
    }
}

/// Sizes the embedded ``VideoView`` and re-applies the track once bounds are non-zero (chat corner / inline).
final class BroadcastInlineVideoHostView: UIView {
    let videoView = VideoView()
    var onDidLayoutVideoView: (() -> Void)?

    private var lastNotifiedBounds: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        videoView.layoutMode = .fit
        videoView.backgroundColor = .black
        addSubview(videoView)
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        videoView.frame = bounds
        let size = bounds.size
        guard size.width > 1, size.height > 1 else { return }
        videoView.setNeedsLayout()
        videoView.layoutIfNeeded()

        let sizeChanged = abs(size.width - lastNotifiedBounds.width) > 0.5
            || abs(size.height - lastNotifiedBounds.height) > 0.5
        let needsRebind = !videoView.didRenderFirstFrame
        if sizeChanged || (needsRebind && lastNotifiedBounds == .zero) {
            lastNotifiedBounds = size
            onDidLayoutVideoView?()
        } else if needsRebind {
            onDidLayoutVideoView?()
        }
    }
}