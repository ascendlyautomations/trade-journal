import SwiftUI
import UIKit

/// Authoritative Feed + Profile image renderer for Posts, Trades, and Achievements.
struct TradeTraxsContentImage: View {
    enum Surface: String {
        case feed
        case profile
    }

    let mediaID: String
    let reference: MediaReference?
    let purpose: ImagePurpose
    let imagePipeline: any ImagePipeline
    var surface: Surface = .feed
    var displayMode: AdaptiveMediaDisplayMode? = nil
    var presentationOverride: ContentImagePresentation? = nil
    /// Fixed width/height for profile thumbnails — when set, uses that box instead of full card width.
    var fixedSize: CGSize? = nil
    var backgroundColor: Color? = nil

    @Environment(\.displayScale) private var displayScale
    @Environment(\.themeColors) private var colors
    @State private var displayImage: UIImage?

    var body: some View {
        Group {
            if let displayImage {
                renderedImage(displayImage)
            } else if reference == nil {
                Color.clear.frame(height: fixedSize?.height ?? 0)
            } else {
                loadingPlaceholder
            }
        }
        .task(id: "\(reference?.id ?? "")|\(purpose.rawValue)|\(displayScale)") {
            await loadDisplayImage()
        }
    }

    @ViewBuilder
    private func renderedImage(_ image: UIImage) -> some View {
        let aspect = MediaImageOrientation.aspectRatio(of: image)
        let bg = backgroundColor ?? colors.fillSecondary

        if let fixedSize {
            let presentation = resolvedPresentation(imageAspect: aspect, containerWidth: fixedSize.width)
            let metrics = FeedMediaLayout.frameMetrics(
                containerWidth: fixedSize.width,
                imageAspect: aspect,
                presentation: presentation
            )
            let containerSize = CGSize(
                width: fixedSize.width,
                height: presentation.requiresFramedViewport
                    ? min(fixedSize.height, metrics.containerHeight)
                    : fixedSize.height
            )
            ZStack {
                bg
                ContentImageFramedImage(
                    image: image,
                    presentation: presentation,
                    containerSize: containerSize
                )
            }
            .frame(width: fixedSize.width, height: fixedSize.height)
            .clipped()
            .onAppear {
                CropRenderProbe.log(
                    surface: surface.rawValue,
                    selectedMode: presentation.aspectMode.rawValue,
                    presentationAspectRatio: presentation.presentationAspectRatio,
                    cropRect: presentation.resolvedCrop(imagePixelSize: MediaImageOrientation.pixelSize(of: image)),
                    containerWidth: fixedSize.width,
                    containerHeight: fixedSize.height
                )
            }
        } else {
            AdaptiveInlineMediaContainer(
                imageAspect: aspect,
                feedPresentationForWidth: usesDetailLayout
                    ? nil
                    : { width in
                        resolvedPresentation(imageAspect: aspect, containerWidth: width)
                    },
                renderSurface: surface.rawValue,
                renderMediaID: mediaID,
                background: bg
            ) { metrics in
                let presentation = resolvedPresentation(
                    imageAspect: aspect,
                    containerWidth: metrics.containerWidth
                )
                ContentImageFramedImage(
                    image: image,
                    presentation: presentation,
                    containerSize: CGSize(
                        width: metrics.containerWidth,
                        height: metrics.containerHeight
                    )
                )
            }
        }
    }

    private var loadingPlaceholder: some View {
        ZStack {
            (backgroundColor ?? colors.fillPrimary)
            if fixedSize != nil {
                ExperienceSkeleton(
                    height: fixedSize?.height ?? 96,
                    cornerRadius: ExperienceRadius.md
                )
            } else {
                ExperienceLoadingSpinner()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
            }
        }
        .frame(width: fixedSize?.width, height: fixedSize?.height)
    }

    private var usesDetailLayout: Bool {
        if case .some(.originalDetail) = displayMode { return true }
        return false
    }

    private func resolvedPresentation(
        imageAspect: CGFloat,
        containerWidth: CGFloat
    ) -> ContentImagePresentation {
        if let presentationOverride { return presentationOverride }
        if let fromReference = reference?.imagePresentation { return fromReference }
        if let reference,
           let stored = ContentImagePresentationStore.presentation(forMediaURL: reference.id) {
            return stored
        }
        return ContentImagePresentation.inferredLegacy(imageAspect: imageAspect)
    }

    private func loadDisplayImage() async {
        guard let reference else {
            displayImage = nil
            return
        }
        do {
            let data = try await imagePipeline.data(
                for: ImageRequest(
                    reference: reference,
                    purpose: purpose,
                    maxPixelSize: nil,
                    allowsProgressiveLoading: true
                )
            )
            let scale = displayScale
            let decoded = await Task.detached(priority: .userInitiated) {
                UIImage(data: data, scale: scale)
            }.value
            displayImage = decoded.map { MediaImageOrientation.normalized($0) }
        } catch {
            displayImage = nil
        }
    }
}

/// Renders an image inside a viewport using normalized crop metadata.
struct ContentImageFramedImage: View {
    let image: UIImage
    let presentation: ContentImagePresentation
    let containerSize: CGSize

    private var pixelSize: CGSize {
        MediaImageOrientation.pixelSize(of: image)
    }

    var body: some View {
        let frameSize = containerSize
        if presentation.usesFillCrop,
           let draw = ContentImagePresentation.drawRect(
            imagePixelSize: pixelSize,
            containerSize: frameSize,
            presentation: presentation
           ) {
            ZStack(alignment: .topLeading) {
                Color.clear
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: draw.width, height: draw.height)
                    .offset(x: draw.x, y: draw.y)
            }
            .frame(width: frameSize.width, height: frameSize.height)
            .clipped()
        } else {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(
                    MediaImageOrientation.aspectRatio(of: image),
                    contentMode: .fit
                )
                .frame(width: frameSize.width, height: frameSize.height)
        }
    }
}

typealias FeedMediaFramedImage = ContentImageFramedImage

/// UIKit counterpart for interactive pinch surfaces.
final class ContentImageFramedImageUIView: UIView {
    let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        imageView.contentMode = .scaleToFill
        imageView.clipsToBounds = true
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(
        image: UIImage,
        presentation: ContentImagePresentation,
        containerSize: CGSize
    ) {
        imageView.image = image
        let pixelSize = MediaImageOrientation.pixelSize(of: image)
        if presentation.usesFillCrop,
           let draw = ContentImagePresentation.drawRect(
            imagePixelSize: pixelSize,
            containerSize: containerSize,
            presentation: presentation
           ) {
            imageView.contentMode = .scaleToFill
            imageView.frame = CGRect(
                x: draw.x,
                y: draw.y,
                width: draw.width,
                height: draw.height
            )
        } else {
            imageView.contentMode = .scaleAspectFit
            imageView.frame = CGRect(origin: .zero, size: containerSize)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard imageView.image != nil else { return }
        if imageView.contentMode == .scaleAspectFit {
            imageView.frame = bounds
        }
    }
}

typealias FeedMediaFramedImageUIView = ContentImageFramedImageUIView
