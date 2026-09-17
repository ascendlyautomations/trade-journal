import SwiftUI
import UIKit

/// Progressive image load + Photos-style pinch zoom via ``UIScrollView``.
struct ZoomableAsyncImageView: View {
    let reference: MediaReference?
    let purpose: ImagePurpose
    let imagePipeline: any ImagePipeline
    var maxPixelSize: Int? = 2_048
    /// Live zoom scale (1 = fit). Used to gate swipe-to-dismiss.
    var zoomScale: Binding<CGFloat>? = nil

    @Environment(\.themeColors) private var colors
    @Environment(\.displayScale) private var displayScale
    @State private var uiImage: UIImage?
    @State private var didFail = false

    var body: some View {
        ZStack {
            Color.black

            if let uiImage {
                ZoomableUIImageView(image: uiImage, zoomScale: zoomScale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if didFail || reference == nil {
                ExperienceIcon(icon: .chart, size: .xl, color: colors.tertiaryText)
            } else {
                ExperienceLoadingSpinner()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: "\(reference?.id ?? "")|\(displayScale)") {
            await load()
        }
    }

    private func load() async {
        guard let reference else {
            uiImage = nil
            didFail = false
            return
        }
        didFail = false
        do {
            let data = try await imagePipeline.data(
                for: ImageRequest(
                    reference: reference,
                    purpose: purpose,
                    maxPixelSize: maxPixelSize,
                    allowsProgressiveLoading: true
                )
            )
            let scale = displayScale
            let decoded = await Task.detached(priority: .userInitiated) {
                guard let raw = UIImage(data: data, scale: scale) else { return nil as UIImage? }
                return MediaImageOrientation.normalized(raw)
            }.value
            guard let decoded else {
                didFail = true
                uiImage = nil
                return
            }
            uiImage = decoded
        } catch {
            didFail = true
            uiImage = nil
        }
    }
}

/// Fills SwiftUI layout bounds; scroll view tracks container size for aspect-fit centering.
private final class ZoomableImageHostView: UIView {
    var onBoundsChange: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onBoundsChange?()
    }
}

/// Native pinch-to-zoom host.
private struct ZoomableUIImageView: UIViewRepresentable {
    let image: UIImage
    var zoomScale: Binding<CGFloat>?

    func makeUIView(context: Context) -> ZoomableImageHostView {
        let host = ZoomableImageHostView()
        host.backgroundColor = .clear

        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: host.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.tag = 100
        scrollView.addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        context.coordinator.hostView = host
        context.coordinator.scrollView = scrollView
        context.coordinator.imageView = imageView
        context.coordinator.zoomScale = zoomScale

        host.onBoundsChange = { [weak coordinator = context.coordinator] in
            coordinator?.layoutImageIfNeeded(force: false)
        }

        return host
    }

    func updateUIView(_ host: ZoomableImageHostView, context: Context) {
        guard let scrollView = context.coordinator.scrollView,
              let imageView = context.coordinator.imageView
        else { return }
        context.coordinator.zoomScale = zoomScale
        let imageChanged = imageView.image !== image
        imageView.image = image
        if imageChanged {
            context.coordinator.hasLaidOut = false
        }
        context.coordinator.layoutImageIfNeeded(force: imageChanged || context.coordinator.lastBounds != scrollView.bounds.size)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var hostView: ZoomableImageHostView?
        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?
        var zoomScale: Binding<CGFloat>?
        var hasLaidOut = false
        var lastBounds: CGSize = .zero

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImage()
            zoomScale?.wrappedValue = scrollView.zoomScale
        }

        func scrollViewDidEndZooming(
            _ scrollView: UIScrollView,
            with view: UIView?,
            atScale scale: CGFloat
        ) {
            zoomScale?.wrappedValue = scale
        }

        func layoutImageIfNeeded(force: Bool) {
            guard force || !hasLaidOut else { return }
            layoutImage()
        }

        func layoutImage() {
            guard let scrollView, let imageView, let image = imageView.image else { return }
            let size = scrollView.bounds.size
            guard size.width > 1, size.height > 1 else { return }

            let wasZoomed = scrollView.zoomScale > 1.001
            if !wasZoomed {
                scrollView.zoomScale = 1
                zoomScale?.wrappedValue = 1
            }

            let pixels = MediaImageOrientation.visualPixelSize(of: image)
            guard pixels.width > 0, pixels.height > 0 else { return }

            let widthRatio = size.width / pixels.width
            let heightRatio = size.height / pixels.height
            let scale = min(widthRatio, heightRatio)
            let fitted = CGSize(
                width: pixels.width * scale,
                height: pixels.height * scale
            )

            imageView.frame = CGRect(origin: .zero, size: fitted)
            scrollView.contentSize = fitted
            lastBounds = size
            hasLaidOut = true
            centerImage()
        }

        private func centerImage() {
            guard let scrollView else { return }
            let bounds = scrollView.bounds.size
            let content = scrollView.contentSize
            let insetX = max((bounds.width - content.width) * 0.5, 0)
            let insetY = max((bounds.height - content.height) * 0.5, 0)
            scrollView.contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > 1 {
                scrollView.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let rect = zoomRect(for: scrollView.maximumZoomScale * 0.5, center: point, in: scrollView)
                scrollView.zoom(to: rect, animated: true)
            }
        }

        private func zoomRect(for scale: CGFloat, center: CGPoint, in scrollView: UIScrollView) -> CGRect {
            let size = CGSize(
                width: scrollView.bounds.width / scale,
                height: scrollView.bounds.height / scale
            )
            return CGRect(
                x: center.x - size.width / 2,
                y: center.y - size.height / 2,
                width: size.width,
                height: size.height
            )
        }
    }
}
