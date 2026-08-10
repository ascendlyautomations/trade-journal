import SwiftUI
import UIKit

/// Progressive image load + Photos-style pinch zoom via ``UIScrollView``.
struct ZoomableAsyncImageView: View {
    let reference: MediaReference?
    let purpose: ImagePurpose
    let imagePipeline: any ImagePipeline
    var maxPixelSize: Int? = 2_048

    @Environment(\.themeColors) private var colors
    @Environment(\.displayScale) private var displayScale
    @State private var uiImage: UIImage?
    @State private var didFail = false

    var body: some View {
        ZStack {
            colors.fillPrimary

            if let uiImage {
                ZoomableUIImageView(image: uiImage)
            } else if didFail || reference == nil {
                ExperienceIcon(icon: .chart, size: .xl, color: colors.tertiaryText)
            } else {
                ExperienceLoadingSpinner()
            }
        }
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
                UIImage(data: data, scale: scale)
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

/// Native pinch-to-zoom host.
private struct ZoomableUIImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never

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

        context.coordinator.scrollView = scrollView
        context.coordinator.imageView = imageView
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        guard let imageView = context.coordinator.imageView else { return }
        imageView.image = image
        context.coordinator.layoutImage()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImage()
        }

        func layoutImage() {
            guard let scrollView, let imageView, let image = imageView.image else { return }
            scrollView.zoomScale = 1
            let size = scrollView.bounds.size
            guard size.width > 0, size.height > 0 else { return }

            let imageSize = image.size
            let widthRatio = size.width / imageSize.width
            let heightRatio = size.height / imageSize.height
            let scale = min(widthRatio, heightRatio)
            let fitted = CGSize(
                width: imageSize.width * scale,
                height: imageSize.height * scale
            )
            imageView.frame = CGRect(origin: .zero, size: fitted)
            scrollView.contentSize = fitted
            centerImage()
        }

        private func centerImage() {
            guard let scrollView, let imageView else { return }
            let bounds = scrollView.bounds.size
            let content = imageView.frame.size
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
