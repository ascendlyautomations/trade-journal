import SwiftUI
import UIKit

// MARK: - Debug probe

#if DEBUG
enum InteractiveImageZoomProbe {
    static func log(_ message: String) {
        print("[InteractiveImageZoom] \(message)")
    }

    static func describe(_ rect: CGRect) -> String {
        "(\(Int(rect.origin.x)),\(Int(rect.origin.y)),\(Int(rect.width))x\(Int(rect.height)))"
    }

    static func describe(_ point: CGPoint) -> String {
        "(\(Int(point.x)),\(Int(point.y)))"
    }
}
#else
enum InteractiveImageZoomProbe {
    static func log(_ message: String) {}
    static func describe(_ rect: CGRect) -> String { "" }
    static func describe(_ point: CGPoint) -> String { "" }
}
#endif

// MARK: - SwiftUI entry (Feed + detail image renderer with interactive zoom)

/// Shared interactive image for Feed and detail — identical aspect-fit presentation.
///
/// Feed and Post/Trade detail use the same container sizing and `scaleAspectFit` UIKit
/// renderer. Only ``deliveryQuality`` differs (640px feed egress vs full-resolution detail).
/// Stored crop metadata is never reapplied — the baked/uploaded bitmap is shown as-is.
struct InteractiveImageView: View {
    let mediaID: String
    let reference: MediaReference?
    let purpose: ImagePurpose
    let imagePipeline: any ImagePipeline
    var emptyIcon: AppIcon = .photo
    var accessibilityIdentifier: String = "interactive.media"
    /// Feed uses `.feedDisplay` (640px). Detail defaults to `.feedDetail` (1280px); pinch upgrades to `.fullResolution`.
    var deliveryQuality: ImageDeliveryQuality = .feedDisplay
    /// DEBUG pipeline audit label — `feed` or `detail`.
    var auditSurface: String = ""
    var onSingleTap: (() -> Void)?
    var onDoubleTapLike: (() -> Void)?

    @Environment(\.displayScale) private var displayScale
    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayImage: UIImage?
    @State private var didFail = false
    @State private var showLikeHeart = false
    @State private var wantsFullResolution = false

    var body: some View {
        Group {
            if let displayImage {
                let aspect = MediaImageOrientation.visualAspectRatio(of: displayImage)
                let pixels = MediaImageOrientation.visualPixelSize(of: displayImage)
                // Feed and detail share aspect-fit rendering; only URL delivery differs.
                AdaptiveInlineMediaContainer(
                    imageAspect: aspect,
                    feedPresentationForWidth: nil,
                    renderSurface: "detail-parity",
                    renderMediaID: mediaID,
                    background: Color.clear
                ) { metrics in
                    InteractiveImageRepresentable(
                        mediaID: mediaID,
                        storageReference: reference?.id ?? "",
                        deliveryQuality: effectiveDeliveryQuality,
                        auditSurface: auditSurface,
                        image: displayImage,
                        backgroundColor: .clear,
                        containerSize: CGSize(
                            width: metrics.containerWidth,
                            height: metrics.containerHeight
                        ),
                        onSingleTap: onSingleTap,
                        onDoubleTapLike: onDoubleTapLike.map { action in
                            {
                                presentLikeFeedback()
                                action()
                            }
                        },
                        onPinchDeepZoom: {
                            if deliveryQuality != .fullResolution {
                                wantsFullResolution = true
                            }
                        }
                    )
                    .onAppear {
                        #if DEBUG
                        FeedImageRenderProbe.log(
                            mediaID: mediaID,
                            surface: deliveryQuality == .fullResolution ? "detail" : "feed",
                            deliveryQuality: deliveryQuality.rawValue,
                            decodedPixels: pixels,
                            containerSize: CGSize(
                                width: metrics.containerWidth,
                                height: metrics.containerHeight
                            ),
                            contentMode: "scaleAspectFit",
                            imageViewFrame: nil,
                            layoutMode: "detailFit"
                        )
                        FeedImageDisplayProbe.log(
                            mediaID: mediaID,
                            decodedAspect: aspect,
                            containerWidth: metrics.containerWidth,
                            storedHadCropRect: false,
                            presentation: .naturalFit(imageAspect: aspect),
                            usesDetailLikeLayout: true
                        )
                        #endif
                    }
                }
            } else if didFail || reference == nil {
                placeholder
            } else {
                loading
            }
        }
        .overlay {
            LikeFeedbackOverlay(isVisible: showLikeHeart, reduceMotion: reduceMotion)
        }
        .task(id: "\(reference?.id ?? "")|\(purpose.rawValue)|\(effectiveDeliveryQuality.rawValue)|\(displayScale)") {
            await loadDisplayImage()
        }
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityAddTraits(.isImage)
    }

    private var placeholder: some View {
        ZStack {
            colors.fillPrimary
            ExperienceIcon(icon: emptyIcon, size: .xl, color: colors.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
    }

    private var loading: some View {
        ZStack {
            colors.fillPrimary
            ExperienceLoadingSpinner()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
    }

    private func presentLikeFeedback() {
        ExperienceHaptics.play(.impactLight)
        if reduceMotion {
            showLikeHeart = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 280_000_000)
                showLikeHeart = false
            }
            return
        }
        ExperienceMotion.withAnimation(MotionSpring.bouncy.animation, reduceMotion: false) {
            showLikeHeart = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 520_000_000)
            ExperienceMotion.withAnimation(
                MotionCurve.easeOut.animation(duration: .fast),
                reduceMotion: false
            ) {
                showLikeHeart = false
            }
        }
    }

    private var effectiveDeliveryQuality: ImageDeliveryQuality {
        if wantsFullResolution { return .fullResolution }
        return deliveryQuality
    }

    private func loadDisplayImage() async {
        guard let reference else {
            displayImage = nil
            didFail = false
            return
        }

        let requestKey = reference.id
        let targetQuality = effectiveDeliveryQuality
        let cacheKey = ImageCacheKey.make(
            referenceID: reference.id,
            purpose: purpose,
            deliveryQuality: targetQuality,
            maxPixelSize: nil
        )
        let traceID = FeedImageTimingTrace.begin(
            mediaID: mediaID,
            cacheKey: cacheKey,
            surface: auditSurface.isEmpty ? "unknown" : auditSurface,
            deliveryQuality: targetQuality.rawValue
        )
        var request = ImageRequest(
            reference: reference,
            purpose: purpose,
            maxPixelSize: nil,
            allowsProgressiveLoading: true,
            deliveryQuality: targetQuality,
            auditSurface: auditSurface,
            auditMediaID: mediaID,
            imageTraceCorrelationID: traceID
        )

        didFail = false
        FeedImageProbe.log(id: mediaID, event: .requestStarted, url: requestKey)

        if let best = await imagePipeline.bestCachedImageDataWithTier(for: request) {
            let probeEvent: FeedImageProbe.Event = best.tier == .memory ? .cacheHitMemory : .cacheHitDisk
            FeedImageProbe.log(id: mediaID, event: probeEvent, url: requestKey)
            let sourceLabel: String = {
                switch (best.tier, best.quality == targetQuality) {
                case (.memory, true): return "memory"
                case (.disk, true): return "disk"
                case (.memory, false): return "memory-tier-\(best.quality.rawValue)"
                case (.disk, false): return "disk-tier-\(best.quality.rawValue)"
                }
            }()
            await assignDisplayImage(
                from: best.data,
                requestKey: requestKey,
                cacheKey: cacheKey,
                source: sourceLabel,
                traceID: traceID,
                notifyViewport: true,
                viewportOutcome: .cacheHit
            )
            if best.quality == targetQuality {
                FeedImageTimingTrace.complete(traceID)
                return
            }
        }

        FeedImageProbe.log(id: mediaID, event: .networkStarted, url: requestKey)

        do {
            request.imageTraceCorrelationID = traceID
            let data = try await imagePipeline.data(for: request)
            await assignDisplayImage(
                from: data,
                requestKey: requestKey,
                cacheKey: cacheKey,
                source: "network",
                traceID: traceID,
                notifyViewport: true,
                viewportOutcome: .loaded
            )
            FeedImageTimingTrace.complete(traceID)
        } catch is CancellationError {
            FeedImageTimingTrace.cancelled(traceID)
            return
        } catch {
            guard reference.id == requestKey else { return }
            didFail = true
            displayImage = nil
            FeedImageTimingTrace.failed(traceID, message: String(describing: error))
            if auditSurface == "feed" {
                FeedImageViewportReadiness.noteMediaResolved(entryID: mediaID, outcome: .failed)
            }
        }
    }

    @MainActor
    private func assignDisplayImage(
        from data: Data,
        requestKey: String,
        cacheKey: String,
        source: String,
        traceID: UUID? = nil,
        notifyViewport: Bool = false,
        viewportOutcome: FeedImageViewportReadiness.Outcome = .loaded
    ) async {
        guard reference?.id == requestKey else {
            FeedImageProbe.log(id: mediaID, event: .staleCompletionDropped, url: requestKey)
            return
        }

        if let traceID {
            FeedImageTimingTrace.event(traceID, "decode.start")
        }
        let scale = displayScale
        let normalized = await Task.detached(priority: .userInitiated) {
            guard let decoded = UIImage(data: data, scale: scale) else { return nil as UIImage? }
            return MediaImageOrientation.normalized(decoded)
        }.value
        if let traceID {
            FeedImageTimingTrace.event(traceID, "decode.end")
        }

        guard reference?.id == requestKey else {
            FeedImageProbe.log(id: mediaID, event: .staleCompletionDropped, url: requestKey)
            return
        }

        guard let normalized else {
            didFail = true
            displayImage = nil
            if let traceID {
                FeedImageTimingTrace.failed(traceID, message: "decodeFailed")
            }
            if notifyViewport, auditSurface == "feed" {
                FeedImageViewportReadiness.noteMediaResolved(entryID: mediaID, outcome: .failed)
            }
            return
        }

        let assignSignpost = MainThreadFreezeProbe.begin("detailImage.assignDisplay")
        defer { MainThreadFreezeProbe.end("detailImage.assignDisplay", id: assignSignpost) }

        let pixels = MediaImageOrientation.visualPixelSize(of: normalized)
        FeedImageProbe.log(id: mediaID, event: .imageDecoded, pixels: pixels)

        #if DEBUG
        let postPixels = MediaPipelineAudit.cgPixelSize(of: normalized)
        MediaPipelineAudit.logDecode(
            MediaPipelineAudit.DecodeReport(
                surface: auditSurface.isEmpty ? "unknown" : auditSurface,
                mediaID: mediaID,
                storageReference: requestKey,
                deliveryQuality: deliveryQuality.rawValue,
                cacheKey: cacheKey,
                source: source,
                preNormalizeOrientation: MediaPipelineAudit.orientationLabel(normalized.imageOrientation),
                preNormalizePixelWidth: postPixels.width,
                preNormalizePixelHeight: postPixels.height,
                preNormalizeSize: MediaPipelineAudit.uiImagePointSizeLabel(normalized),
                preNormalizeScale: normalized.scale,
                postNormalizePixelWidth: postPixels.width,
                postNormalizePixelHeight: postPixels.height,
                postNormalizeSize: MediaPipelineAudit.uiImagePointSizeLabel(normalized),
                postNormalizeScale: normalized.scale,
                postNormalizeOrientation: MediaPipelineAudit.orientationLabel(normalized.imageOrientation)
            )
        )
        #endif

        displayImage = normalized
        if let traceID {
            FeedImageTimingTrace.event(traceID, "image.assigned", detail: source)
        }
        FeedMediaReadyProbe.log(
            itemID: mediaID,
            kind: mediaReadyKind,
            source: source
        )
        if notifyViewport, auditSurface == "feed" {
            FeedImageViewportReadiness.noteMediaResolved(entryID: mediaID, outcome: viewportOutcome)
        }
    }

    private var mediaReadyKind: String {
        switch purpose {
        case .tradeScreenshot: return "trade-image"
        case .postImage: return "post-image"
        case .reelThumbnail: return "clip-thumbnail"
        case .profileAvatar: return "avatar"
        case .storyMedia: return "story-image"
        }
    }

}

// MARK: - UIViewRepresentable

private struct InteractiveImageRepresentable: UIViewRepresentable {
    let mediaID: String
    let storageReference: String
    let deliveryQuality: ImageDeliveryQuality
    let auditSurface: String
    let image: UIImage
    let backgroundColor: UIColor
    let containerSize: CGSize
    let onSingleTap: (() -> Void)?
    let onDoubleTapLike: (() -> Void)?
    let onPinchDeepZoom: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            mediaID: mediaID,
            onSingleTap: onSingleTap,
            onDoubleTapLike: onDoubleTapLike,
            onPinchDeepZoom: onPinchDeepZoom
        )
    }

    func makeUIView(context: Context) -> InteractiveImageUIView {
        let view = InteractiveImageUIView(
            mediaID: mediaID,
            storageReference: storageReference,
            deliveryQuality: deliveryQuality,
            auditSurface: auditSurface
        )
        view.coordinator = context.coordinator
        view.backgroundFillColor = backgroundColor
        applyLayout(to: view)
        context.coordinator.rootView = view
        return view
    }

    func updateUIView(_ uiView: InteractiveImageUIView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
        context.coordinator.onDoubleTapLike = onDoubleTapLike
        context.coordinator.onPinchDeepZoom = onPinchDeepZoom
        uiView.coordinator = context.coordinator
        uiView.backgroundFillColor = backgroundColor
        guard !uiView.isPinching else { return }
        applyLayout(to: uiView)
        uiView.setNeedsLayout()
        if uiView.bounds.width > 0, uiView.bounds.height > 0 {
            uiView.layoutIfNeeded()
        }
    }

    private func applyLayout(to view: InteractiveImageUIView) {
        view.applyDetailFit(image: image, containerSize: containerSize)
    }

    final class Coordinator: NSObject {
        let mediaID: String
        var onSingleTap: (() -> Void)?
        var onDoubleTapLike: (() -> Void)?
        var onPinchDeepZoom: (() -> Void)?
        weak var rootView: InteractiveImageUIView?

        init(
            mediaID: String,
            onSingleTap: (() -> Void)?,
            onDoubleTapLike: (() -> Void)?,
            onPinchDeepZoom: (() -> Void)? = nil
        ) {
            self.mediaID = mediaID
            self.onSingleTap = onSingleTap
            self.onDoubleTapLike = onDoubleTapLike
            self.onPinchDeepZoom = onPinchDeepZoom
        }
    }
}

// MARK: - UIKit root (pixels + pinch/tap — recognizer stays here; overlay follows live)

/// Root interactive surface — `UIImageView` displays pixels; root owns recognizers.
final class InteractiveImageUIView: UIView, UIGestureRecognizerDelegate {
    let mediaID: String
    let storageReference: String
    let deliveryQuality: ImageDeliveryQuality
    let auditSurface: String
    let imageView = UIImageView()

    fileprivate weak var coordinator: InteractiveImageRepresentable.Coordinator?

    private var displayedImage: UIImage?
    private var lastAppliedMediaID: String?
    private var didLogImageAssigned = false

    var backgroundFillColor: UIColor = .clear {
        didSet {
            guard !isPinching else { return }
            backgroundColor = backgroundFillColor
        }
    }

    private(set) var isPinching = false

    private var pinchRecognizer: UIPinchGestureRecognizer!
    private var singleTapRecognizer: UITapGestureRecognizer?
    private var doubleTapRecognizer: UITapGestureRecognizer?
    private weak var scrollView: UIScrollView?
    private weak var overlayImageView: UIImageView?
    private var didLogMount = false

    private var pinchStartFrame: CGRect = .zero
    private var pinchStartMidpoint: CGPoint = .zero
    private var normalizedPinchAnchor = CGPoint(x: 0.5, y: 0.5)
    private var livePinchScale: CGFloat = 1

    init(
        mediaID: String,
        storageReference: String,
        deliveryQuality: ImageDeliveryQuality,
        auditSurface: String
    ) {
        self.mediaID = mediaID
        self.storageReference = storageReference
        self.deliveryQuality = deliveryQuality
        self.auditSurface = auditSurface
        super.init(frame: .zero)
        isUserInteractionEnabled = true
        isMultipleTouchEnabled = true
        clipsToBounds = true

        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false
        imageView.clipsToBounds = true
        addSubview(imageView)

        pinchRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinchRecognizer.delegate = self
        pinchRecognizer.cancelsTouchesInView = false
        addGestureRecognizer(pinchRecognizer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setImage(_ image: UIImage) {
        guard !isPinching else { return }
        displayedImage = image
        imageView.image = image
        imageView.transform = .identity
        imageView.alpha = 1
        imageView.isHidden = false
        didLogImageAssigned = false
        setNeedsLayout()
    }

    func applyDetailFit(image: UIImage, containerSize: CGSize) {
        let imageChanged = displayedImage !== image
        if lastAppliedMediaID != mediaID || imageChanged {
            imageView.transform = .identity
            livePinchScale = 1
            lastAppliedMediaID = mediaID
            #if DEBUG
            InteractiveImageZoomProbe.log(
                "reset id=\(mediaID) zoomScale=1 minimumZoomScale=1 transform=identity"
            )
            #endif
        }
        setImage(image)
        relayoutImageSubview(expectedContainerSize: containerSize)
    }

    private func relayoutImageSubview(expectedContainerSize: CGSize? = nil) {
        guard !isPinching else { return }
        guard bounds.width > 0, bounds.height > 0 else { return }

        imageView.contentMode = .scaleAspectFit
        imageView.frame = bounds

        #if DEBUG
        if let image = displayedImage ?? imageView.image {
            let pixels = MediaImageOrientation.pixelSize(of: image)
            let contentModeLabel: String
            switch imageView.contentMode {
            case .scaleAspectFit: contentModeLabel = "scaleAspectFit"
            case .scaleToFill: contentModeLabel = "scaleToFill"
            case .scaleAspectFill: contentModeLabel = "scaleAspectFill"
            default: contentModeLabel = String(describing: imageView.contentMode)
            }
            MediaPipelineAudit.logRender(
                MediaPipelineAudit.RenderReport(
                    surface: auditSurface.isEmpty ? "unknown" : auditSurface,
                    mediaID: mediaID,
                    storageReference: storageReference,
                    deliveryQuality: deliveryQuality.rawValue,
                    decodedPixelWidth: Int(pixels.width),
                    decodedPixelHeight: Int(pixels.height),
                    containerBounds: MediaPipelineAudit.describeRect(bounds),
                    imageViewBounds: MediaPipelineAudit.describeRect(imageView.bounds),
                    imageViewFrame: MediaPipelineAudit.describeRect(imageView.frame),
                    contentMode: contentModeLabel
                )
            )
            FeedImageRenderProbe.log(
                mediaID: mediaID,
                surface: auditSurface.isEmpty ? "interactive" : auditSurface,
                deliveryQuality: deliveryQuality.rawValue,
                decodedPixels: pixels,
                containerSize: expectedContainerSize ?? bounds.size,
                contentMode: contentModeLabel,
                imageViewFrame: imageView.frame,
                layoutMode: "detailFit"
            )
        }
        #endif

        logImageAssignedIfNeeded()
    }

    private func logImageAssignedIfNeeded() {
        guard !didLogImageAssigned else { return }
        guard imageView.image != nil else { return }
        guard bounds.width > 0, bounds.height > 0 else { return }
        guard imageView.bounds.width > 0, imageView.bounds.height > 0 else { return }
        didLogImageAssigned = true
        FeedImageProbe.log(
            id: mediaID,
            event: .imageAssigned,
            rootBounds: bounds,
            imageBounds: imageView.bounds,
            mainThread: Thread.isMainThread
        )
    }

    func installTapRecognizersIfNeeded() {
        guard singleTapRecognizer == nil, doubleTapRecognizer == nil else { return }

        if coordinator?.onDoubleTapLike != nil {
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = 2
            doubleTap.numberOfTouchesRequired = 1
            doubleTap.delegate = self
            doubleTap.cancelsTouchesInView = false
            addGestureRecognizer(doubleTap)
            doubleTapRecognizer = doubleTap
        }

        if coordinator?.onSingleTap != nil {
            let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
            singleTap.numberOfTapsRequired = 1
            singleTap.numberOfTouchesRequired = 1
            singleTap.delegate = self
            singleTap.cancelsTouchesInView = false
            if let doubleTapRecognizer {
                singleTap.require(toFail: doubleTapRecognizer)
            }
            addGestureRecognizer(singleTap)
            singleTapRecognizer = singleTap
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        scrollView = enclosingScrollView
        installTapRecognizersIfNeeded()
        guard !didLogMount else { return }
        didLogMount = true
        FeedImageProbe.log(
            id: mediaID,
            event: .mount,
            rootBounds: bounds,
            imageBounds: imageView.bounds
        )
        InteractiveImageZoomProbe.log("mounted id=\(mediaID)")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !isPinching else { return }
        relayoutImageSubview()
        FeedImageProbe.log(
            id: mediaID,
            event: .layoutSubviews,
            rootBounds: bounds,
            imageBounds: imageView.bounds
        )
        logLayoutMetrics()
    }

    private func logLayoutMetrics() {
        let rootBounds = InteractiveImageZoomProbe.describe(bounds)
        let imageBounds = InteractiveImageZoomProbe.describe(imageView.bounds)
        let windowFrame: String
        if let window {
            windowFrame = InteractiveImageZoomProbe.describe(convert(bounds, to: window))
        } else {
            windowFrame = "no-window"
        }
        InteractiveImageZoomProbe.log(
            "rootBounds=\(rootBounds) imageBounds=\(imageBounds) windowFrame=\(windowFrame)"
        )
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        guard event?.type == .touches else { return result }
        let winner = result.map { String(describing: type(of: $0)) } ?? "nil"
        let touchCount = event?.allTouches?.filter {
            switch $0.phase {
            case .ended, .cancelled: return false
            default: return true
            }
        }.count ?? 0
        InteractiveImageZoomProbe.log(
            "HIT id=\(mediaID) point=(\(Int(point.x)),\(Int(point.y))) "
                + "activeTouches=\(touchCount) winner=\(winner)"
        )
        return result
    }

    @objc private func handleSingleTap(_ recognizer: UITapGestureRecognizer) {
        guard !isPinching else { return }
        coordinator?.onSingleTap?()
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard !isPinching else { return }
        coordinator?.onDoubleTapLike?()
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        guard let window else { return }

        switch recognizer.state {
        case .began:
            beginPinch(recognizer, in: window)
        case .changed:
            updatePinch(recognizer, in: window)
        case .ended, .cancelled, .failed:
            endPinch(in: window)
        default:
            break
        }
    }

    private func beginPinch(_ recognizer: UIPinchGestureRecognizer, in window: UIWindow) {
        guard let image = imageView.image else { return }
        dismissOverlay(animated: false)

        let frame = convert(bounds, to: window)
        guard frame.width > 0, frame.height > 0 else { return }

        let midpoint = pinchMidpoint(recognizer, in: window)
        let overlay = UIImageView(image: image)
        overlay.contentMode = .scaleAspectFit
        overlay.clipsToBounds = false
        overlay.isUserInteractionEnabled = false
        overlay.frame = frame
        overlay.layer.zPosition = 10_000
        window.addSubview(overlay)

        overlayImageView = overlay
        pinchStartFrame = frame
        pinchStartMidpoint = midpoint
        normalizedPinchAnchor = normalizedPoint(midpoint, in: frame)
        livePinchScale = 1
        isPinching = true
        coordinator?.onPinchDeepZoom?()

        scrollView?.isScrollEnabled = false
        imageView.alpha = 0

        applyPinchTransform(to: overlay, scale: 1, translation: .zero)

        InteractiveImageZoomProbe.log(
            "began scale=\(String(format: "%.3f", recognizer.scale)) "
                + "midpoint=\(InteractiveImageZoomProbe.describe(midpoint)) "
                + "frame=\(InteractiveImageZoomProbe.describe(frame))"
        )
    }

    private func updatePinch(_ recognizer: UIPinchGestureRecognizer, in window: UIWindow) {
        guard isPinching, let overlay = overlayImageView else { return }

        let scale = min(max(recognizer.scale, 1), 4)
        let midpoint = pinchMidpoint(recognizer, in: window)
        let proposedTranslation = CGPoint(
            x: midpoint.x - pinchStartMidpoint.x,
            y: midpoint.y - pinchStartMidpoint.y
        )
        livePinchScale = scale

        let translation = clampedTranslation(
            proposedTranslation,
            scale: scale,
            overlay: overlay
        )
        applyPinchTransform(to: overlay, scale: scale, translation: translation)

        InteractiveImageZoomProbe.log(
            "changed scale=\(String(format: "%.3f", scale)) "
                + "midpoint=\(InteractiveImageZoomProbe.describe(midpoint)) "
                + "translation=\(InteractiveImageZoomProbe.describe(translation))"
        )
    }

    private func endPinch(in window: UIWindow) {
        guard isPinching else { return }

        let endingScale = livePinchScale
        InteractiveImageZoomProbe.log("ended scale=\(String(format: "%.3f", endingScale))")

        guard let overlay = overlayImageView else {
            restoreAfterPinch()
            return
        }

        let targetFrame = convert(bounds, to: window)
        let reduceMotion = UIAccessibility.isReduceMotionEnabled

        let finish = { [weak self] in
            overlay.removeFromSuperview()
            self?.overlayImageView = nil
            self?.restoreAfterPinch()
        }

        if reduceMotion {
            finish()
            return
        }

        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            overlay.transform = .identity
            overlay.frame = targetFrame
        } completion: { _ in
            finish()
        }
    }

    private func restoreAfterPinch() {
        isPinching = false
        livePinchScale = 1
        pinchStartFrame = .zero
        pinchStartMidpoint = .zero
        normalizedPinchAnchor = CGPoint(x: 0.5, y: 0.5)
        imageView.alpha = 1
        imageView.transform = .identity
        scrollView?.isScrollEnabled = true
        setNeedsLayout()
        layoutIfNeeded()
    }

    private func dismissOverlay(animated: Bool) {
        overlayImageView?.removeFromSuperview()
        overlayImageView = nil
    }

    private func applyPinchTransform(to view: UIView, scale: CGFloat, translation: CGPoint) {
        let anchorInWindow = CGPoint(
            x: pinchStartFrame.minX + normalizedPinchAnchor.x * pinchStartFrame.width,
            y: pinchStartFrame.minY + normalizedPinchAnchor.y * pinchStartFrame.height
        )
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: anchorInWindow.x, y: anchorInWindow.y)
        transform = transform.scaledBy(x: scale, y: scale)
        transform = transform.translatedBy(x: -anchorInWindow.x, y: -anchorInWindow.y)
        transform = transform.translatedBy(x: translation.x, y: translation.y)
        view.transform = transform
    }

    /// Keeps the scaled overlay covering the original image viewport — no empty gaps inside.
    private func clampedTranslation(
        _ proposed: CGPoint,
        scale: CGFloat,
        overlay: UIView
    ) -> CGPoint {
        var translation = proposed
        let viewport = pinchStartFrame

        for _ in 0..<4 {
            applyPinchTransform(to: overlay, scale: scale, translation: translation)
            let visual = overlay.frame

            var adjust = CGPoint.zero
            if visual.minX > viewport.minX {
                adjust.x += viewport.minX - visual.minX
            }
            if visual.maxX < viewport.maxX {
                adjust.x += viewport.maxX - visual.maxX
            }
            if visual.minY > viewport.minY {
                adjust.y += viewport.minY - visual.minY
            }
            if visual.maxY < viewport.maxY {
                adjust.y += viewport.maxY - visual.maxY
            }

            if abs(adjust.x) < 0.5, abs(adjust.y) < 0.5 {
                break
            }
            translation.x += adjust.x
            translation.y += adjust.y
        }

        return translation
    }

    private func pinchMidpoint(_ gesture: UIGestureRecognizer, in window: UIWindow) -> CGPoint {
        let count = max(gesture.numberOfTouches, 1)
        var sum = CGPoint.zero
        for index in 0..<count {
            let point = gesture.location(ofTouch: index, in: window)
            sum.x += point.x
            sum.y += point.y
        }
        return CGPoint(x: sum.x / CGFloat(count), y: sum.y / CGFloat(count))
    }

    private func normalizedPoint(_ point: CGPoint, in frame: CGRect) -> CGPoint {
        guard frame.width > 0, frame.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(
            x: min(max((point.x - frame.minX) / frame.width, 0), 1),
            y: min(max((point.y - frame.minY) / frame.height, 0), 1)
        )
    }

    // MARK: UIGestureRecognizerDelegate

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if isPinching { return false }
        let involvesPinch = gestureRecognizer is UIPinchGestureRecognizer
            || otherGestureRecognizer is UIPinchGestureRecognizer
        guard involvesPinch, let scrollView else { return false }
        let involvesScrollPan = gestureRecognizer === scrollView.panGestureRecognizer
            || otherGestureRecognizer === scrollView.panGestureRecognizer
        return involvesScrollPan
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if isPinching {
            return gestureRecognizer is UIPinchGestureRecognizer
        }
        if gestureRecognizer is UIPinchGestureRecognizer {
            return imageView.image != nil
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}

private extension UIView {
    var enclosingScrollView: UIScrollView? {
        var view: UIView? = self
        while let current = view {
            if let scroll = current as? UIScrollView { return scroll }
            view = current.superview
        }
        return nil
    }
}
