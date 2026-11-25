import LiveKit
import UIKit

/// Binds a program ``VideoView`` to a remote track and surfaces the first rendered frame via ``VideoViewDelegate``.
///
/// LiveKit may invoke ``VideoViewDelegate`` off the main queue; all UIKit / ``VideoView`` mutation stays on the main actor.
@MainActor
final class BroadcastProgramVideoViewAttachment: NSObject, VideoViewDelegate {
    var onFirstFrame: (() -> Void)?
    private weak var videoView: VideoView?
    private weak var boundTrack: VideoTrack?
    private var boundRevision: UInt = 0
    private var isDetached = false

    @MainActor
    func apply(incomingTrack: VideoTrack?, revision: UInt, to videoView: VideoView) {
        isDetached = false
        if self.videoView !== videoView {
            self.videoView?.remove(delegate: self)
            self.videoView = videoView
            videoView.add(delegate: self)
        }

        let trackChanged = !Self.tracksEqual(boundTrack, incomingTrack)
        let revisionChanged = revision != boundRevision
        boundTrack = incomingTrack
        boundRevision = revision

        if trackChanged || revisionChanged || videoView.track !== incomingTrack {
            rebind(incomingTrack: incomingTrack, on: videoView)
            return
        }

        if incomingTrack != nil, !videoView.didRenderFirstFrame {
            rebind(incomingTrack: incomingTrack, on: videoView)
            return
        }

        reportFirstFrameIfNeeded(from: videoView)
    }

    @MainActor
    private func rebind(incomingTrack: VideoTrack?, on videoView: VideoView) {
        if videoView.track != nil {
            videoView.track = nil
        }
        videoView.track = incomingTrack
        videoView.setNeedsLayout()
        videoView.layoutIfNeeded()
        reportFirstFrameIfNeeded(from: videoView)
    }

    nonisolated func videoView(_ videoView: VideoView, didUpdate size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        enqueueMainWork { [weak self, weak videoView] in
            guard let self, let videoView else { return }
            self.handleSizeUpdate(on: videoView)
        }
    }

    nonisolated func videoView(_ videoView: VideoView, didUpdate isRendering: Bool) {
        guard isRendering else { return }
        enqueueMainWork { [weak self, weak videoView] in
            guard let self, let videoView else { return }
            self.handleRenderingUpdate(on: videoView)
        }
    }

    @MainActor
    func detach() {
        isDetached = true
        if let videoView {
            videoView.remove(delegate: self)
            videoView.track = nil
        }
        videoView = nil
        boundTrack = nil
        boundRevision = 0
    }

    @MainActor
    private func handleSizeUpdate(on videoView: VideoView) {
        guard !isDetached, self.videoView === videoView else { return }
        if videoView.track != nil, !videoView.didRenderFirstFrame {
            rebind(incomingTrack: boundTrack, on: videoView)
            return
        }
        reportFirstFrameIfNeeded(from: videoView)
    }

    @MainActor
    private func handleRenderingUpdate(on videoView: VideoView) {
        guard !isDetached, self.videoView === videoView else { return }
        reportFirstFrameIfNeeded(from: videoView)
    }

    @MainActor
    private func reportFirstFrameIfNeeded(from videoView: VideoView) {
        guard !isDetached, self.videoView === videoView else { return }
        guard videoView.track != nil else { return }
        guard videoView.didRenderFirstFrame || videoView.isRendering else { return }
        onFirstFrame?()
    }

    private static func tracksEqual(_ lhs: VideoTrack?, _ rhs: VideoTrack?) -> Bool {
        if lhs == nil, rhs == nil { return true }
        guard let lhs, let rhs else { return false }
        return lhs.isEqual(rhs)
    }

    /// Marshals delegate callbacks onto the main actor (LiveKit multicast may call from a worker queue).
    private nonisolated func enqueueMainWork(_ work: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                work()
            }
        } else {
            Task { @MainActor in work() }
        }
    }
}