import CoreGraphics
import SwiftUI
import UIKit

/// Feed/Profile card framing — full width, maximum 4:5 portrait, aspect-fill when cropping.
nonisolated enum FeedMediaLayout {
    /// Tallest allowed Feed/Profile portrait ratio (width / height). 4:5 = 0.8.
    static let minimumFeedAspectRatio: CGFloat = 4.0 / 5.0

    static let minHeight: CGFloat = 120

    struct FrameMetrics: Equatable {
        let containerWidth: CGFloat
        let containerHeight: CGFloat
        let usesFillCrop: Bool
        let viewportAspect: CGFloat
    }

    /// Feed presentation aspect at full card width.
    static func presentationAspect(
        imageAspect: CGFloat,
        aspectOption: ImageCropAspectOption
    ) -> CGFloat {
        let safeAspect = max(imageAspect, 0.01)
        switch aspectOption {
        case .original:
            return max(safeAspect, minimumFeedAspectRatio)
        case .square:
            return 1
        case .portrait:
            return minimumFeedAspectRatio
        case .landscape:
            return 16 / 9
        }
    }

    /// True when the image must be aspect-filled into the presentation viewport.
    static func requiresFillCrop(
        imageAspect: CGFloat,
        aspectOption: ImageCropAspectOption
    ) -> Bool {
        let safeAspect = max(imageAspect, 0.01)
        switch aspectOption {
        case .original:
            return safeAspect < minimumFeedAspectRatio
        case .square, .portrait, .landscape:
            return true
        }
    }

    static func exceedsFeedPortraitLimit(imageAspect: CGFloat) -> Bool {
        max(imageAspect, 0.01) < minimumFeedAspectRatio
    }

    static func frameMetrics(
        containerWidth: CGFloat,
        imageAspect: CGFloat,
        presentation: ContentImagePresentation
    ) -> FrameMetrics {
        guard containerWidth > 0 else {
            return FrameMetrics(
                containerWidth: 0,
                containerHeight: minHeight,
                usesFillCrop: false,
                viewportAspect: 1
            )
        }

        let safeAspect = max(imageAspect, 0.01)
        let presentationAspect = presentation.presentationAspectRatio

        if presentation.requiresFramedViewport {
            let height = max(containerWidth / max(presentationAspect, 0.01), minHeight)
            return FrameMetrics(
                containerWidth: containerWidth,
                containerHeight: height,
                usesFillCrop: true,
                viewportAspect: presentationAspect
            )
        }

        let naturalHeight = max(containerWidth / safeAspect, minHeight)
        return FrameMetrics(
            containerWidth: containerWidth,
            containerHeight: naturalHeight,
            usesFillCrop: false,
            viewportAspect: safeAspect
        )
    }

    static func drawRect(
        imagePixelSize: CGSize,
        frameSize: CGSize,
        presentation: ContentImagePresentation
    ) -> ImageCropMath.DrawRect? {
        ContentImagePresentation.drawRect(
            imagePixelSize: imagePixelSize,
            containerSize: frameSize,
            presentation: presentation
        )
    }

    static func editorViewportSize(
        containerWidth: CGFloat,
        imagePixelSize: CGSize,
        aspectOption: ImageCropAspectOption
    ) -> CGSize {
        guard containerWidth > 0 else { return .zero }
        let imageAspect = max(imagePixelSize.width / max(imagePixelSize.height, 1), 0.01)
        let aspect = presentationAspect(imageAspect: imageAspect, aspectOption: aspectOption)
        let height = max(containerWidth / aspect, minHeight)
        return CGSize(width: containerWidth, height: height)
    }
}

/// How inline uploaded images should be presented.
enum AdaptiveMediaDisplayMode: Equatable, Sendable {
    case feedCard(ContentImagePresentation)
    case originalDetail
}

enum AdaptiveMediaLayout {
    typealias FrameMetrics = FeedMediaLayout.FrameMetrics

    static var minimumFeedAspectRatio: CGFloat { FeedMediaLayout.minimumFeedAspectRatio }
    static var minHeight: CGFloat { FeedMediaLayout.minHeight }

    static func frameMetrics(
        containerWidth: CGFloat,
        imageAspect: CGFloat,
        displayMode: AdaptiveMediaDisplayMode
    ) -> FrameMetrics {
        switch displayMode {
        case .feedCard(let presentation):
            return FeedMediaLayout.frameMetrics(
                containerWidth: containerWidth,
                imageAspect: imageAspect,
                presentation: presentation
            )
        case .originalDetail:
            let height = max(containerWidth / max(imageAspect, 0.01), minHeight)
            return FrameMetrics(
                containerWidth: containerWidth,
                containerHeight: height,
                usesFillCrop: false,
                viewportAspect: imageAspect
            )
        }
    }
}

struct AdaptiveInlineMediaContainer<Content: View>: View {
    let imageAspect: CGFloat
    var feedPresentationForWidth: ((CGFloat) -> ContentImagePresentation)?
    var renderSurface: String = "feed"
    var renderMediaID: String = ""
    let background: Color
    @ViewBuilder var content: (AdaptiveMediaLayout.FrameMetrics) -> Content

    @State private var containerWidth: CGFloat = 0

    private var displayMode: AdaptiveMediaDisplayMode {
        if let feedPresentationForWidth, containerWidth > 0 {
            return .feedCard(feedPresentationForWidth(containerWidth))
        }
        return .originalDetail
    }

    var body: some View {
        Group {
            if containerWidth > 0 {
                let metrics = AdaptiveMediaLayout.frameMetrics(
                    containerWidth: containerWidth,
                    imageAspect: imageAspect,
                    displayMode: displayMode
                )

                content(metrics)
                    .frame(width: metrics.containerWidth, height: metrics.containerHeight)
                    .clipped()
                    .background(background)
                    .contentShape(Rectangle())
                    .onAppear {
                        logRender(metrics: metrics, displayMode: displayMode)
                    }
                    .onChange(of: metrics.containerWidth) { _, _ in
                        logRender(metrics: metrics, displayMode: displayMode)
                    }
            } else {
                Color.clear
                    .aspectRatio(
                        max(imageAspect, FeedMediaLayout.minimumFeedAspectRatio),
                        contentMode: .fit
                    )
                    .frame(maxWidth: .infinity)
                    .background(background)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width in
            guard width > 0, abs(width - containerWidth) > 0.5 else { return }
            containerWidth = width
        }
    }

    private func logRender(
        metrics: AdaptiveMediaLayout.FrameMetrics,
        displayMode: AdaptiveMediaDisplayMode
    ) {
        guard case .feedCard(let presentation) = displayMode else { return }
        CropRenderProbe.log(
            surface: renderSurface,
            selectedMode: presentation.aspectMode.rawValue,
            presentationAspectRatio: presentation.presentationAspectRatio,
            cropRect: presentation.normalizedCrop,
            containerWidth: metrics.containerWidth,
            containerHeight: metrics.containerHeight
        )
    }
}
