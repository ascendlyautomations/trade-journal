import LiveKit
import SwiftUI
import UIKit

/// LiveKit video in a pinch-zoom scroll view — zoom applies to the view layer, not the track subscription.
struct BroadcastStreamZoomableVideoView: UIViewRepresentable {
    var track: VideoTrack?
    var isFullscreen: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ZoomableBroadcastVideoContainer {
        let container = ZoomableBroadcastVideoContainer()
        context.coordinator.container = container
        return container
    }

    func updateUIView(_ uiView: ZoomableBroadcastVideoContainer, context: Context) {
        uiView.videoView.track = track
        uiView.setNeedsLayout()
    }

    final class Coordinator {
        weak var container: ZoomableBroadcastVideoContainer?
    }
}

final class ZoomableBroadcastVideoContainer: UIView, UIScrollViewDelegate {
    let scrollView = UIScrollView()
    let videoView = VideoView()

    private var doubleTapRecognizer: UITapGestureRecognizer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        videoView.layoutMode = .fit
        videoView.backgroundColor = .black
        videoView.translatesAutoresizingMaskIntoConstraints = true
        scrollView.addSubview(videoView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        doubleTapRecognizer = doubleTap
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        videoView.frame = CGRect(origin: .zero, size: size)
        scrollView.contentSize = size
        centerVideoIfNeeded()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        videoView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerVideoIfNeeded()
    }

    func resetZoom() {
        scrollView.setZoomScale(1, animated: true)
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        if scrollView.zoomScale > 1.01 {
            resetZoom()
        } else {
            let point = recognizer.location(in: videoView)
            let zoomRect = zoomRect(for: scrollView.maximumZoomScale / 2, center: point)
            scrollView.zoom(to: zoomRect, animated: true)
        }
    }

    private func zoomRect(for scale: CGFloat, center: CGPoint) -> CGRect {
        let size = scrollView.bounds.size
        let width = size.width / scale
        let height = size.height / scale
        let originX = center.x - width / 2
        let originY = center.y - height / 2
        return CGRect(x: originX, y: originY, width: width, height: height)
    }

    private func centerVideoIfNeeded() {
        let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) * 0.5, 0)
        let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) * 0.5, 0)
        scrollView.contentInset = UIEdgeInsets(top: offsetY, left: offsetX, bottom: offsetY, right: offsetX)
    }
}
