import SwiftUI
import UIKit

/// Shared aspect-fit media for Post / Trade — Instagram-style natural proportions.
///
/// Root layout contract:
/// 1. Load the **same public object bytes the web uses** (`/storage/v1/object/public/...`)
/// 2. Decode at the screen’s display scale (retina) — never `UIImage(data:)` at scale 1.0
/// 3. Size from the bitmap’s aspect ratio (width-driven, height-capped)
/// 4. Never use `scaledToFill` / never crop
///
/// Quality note (web parity): the web feed requests a storage transform when available and
/// **falls back to the original object URL**. Uploads are already capped (~2560px) by
/// `compressScreenshot`. Client longest-edge downsampling here previously produced portrait
/// widths below `screenWidth × scale`, which SwiftUI then **upscaled** → blur.
struct AspectFitMediaView: View {
    let reference: MediaReference?
    let purpose: ImagePurpose
    let imagePipeline: any ImagePipeline
    var accessibilityIdentifier: String = "detail.media"
    var emptyIcon: AppIcon = .photo
    /// When `false`, tap does not open the full-resolution viewer (list previews).
    var allowsFullResolutionViewer: Bool = true
    /// When `false`, omit empty / failed placeholders (Feed text-first layout).
    var showsPlaceholderWhenUnavailable: Bool = true
    /// Double-tap Like callback (like-only). When set, single-tap still opens the viewer if allowed.
    var onDoubleTapLike: (() -> Void)? = nil

    @Environment(\.themeColors) private var colors
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayImage: UIImage?
    @State private var didFail = false
    @State private var showsFullViewer = false
    @State private var showLikeHeart = false

    /// Soft cap for very tall portrait uploads (web `min(58dvh, …)` style).
    private var maxDisplayHeight: CGFloat {
        min(UIScreen.main.bounds.height * 0.58, 720)
    }

    var body: some View {
        Group {
            if let displayImage {
                media(displayImage)
            } else if didFail || reference == nil {
                if showsPlaceholderWhenUnavailable {
                    placeholder
                }
            } else if showsPlaceholderWhenUnavailable {
                loading
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .overlay {
            LikeFeedbackOverlay(isVisible: showLikeHeart, reduceMotion: reduceMotion)
        }
        .modifier(
            AspectFitMediaTapModifier(
                allowsFullResolutionViewer: allowsFullResolutionViewer,
                canOpenViewer: reference != nil && displayImage != nil,
                onDoubleTapLike: onDoubleTapLike.map { action in
                    {
                        presentLikeFeedback()
                        action()
                    }
                },
                onOpenViewer: {
                    ExperienceHaptics.play(.selection)
                    showsFullViewer = true
                }
            )
        )
        .task(id: "\(reference?.id ?? "")|\(purpose.rawValue)|\(displayScale)") {
            await loadDisplayImage()
        }
        .fullScreenCover(isPresented: $showsFullViewer) {
            AspectFitFullImageViewer(
                reference: reference,
                purpose: purpose,
                imagePipeline: imagePipeline
            )
        }
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityAddTraits(.isImage)
        .accessibilityHint(
            allowsFullResolutionViewer && reference != nil
                ? "Opens full resolution viewer"
                : ""
        )
    }

    /// Width-driven aspect box — the image defines height, not a fixed frame.
    private func media(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            // Natural bitmap aspect — do not invent a separate ratio from point size.
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: maxDisplayHeight)
            .background(colors.fillPrimary)
            .background {
                GeometryReader { geo in
                    Color.clear
                        .preference(
                            key: AspectFitMediaSizeKey.self,
                            value: geo.size
                        )
                }
            }
            .onPreferenceChange(AspectFitMediaSizeKey.self) { size in
                guard ImageFidelityTrace.isEnabled, size.width > 0, size.height > 0 else { return }
                let decoded = ImageFidelityTrace.pixelSize(of: image)
                let displayPx = ImageFidelityTrace.PixelSize(
                    width: Int((size.width * displayScale).rounded()),
                    height: Int((size.height * displayScale).rounded())
                )
                ImageFidelityTrace.log(
                    ImageFidelityTrace.StageReport(
                        stage: "swiftui/final-render",
                        url: reference?.id,
                        pixelSize: decoded,
                        uiImagePointSize: image.size,
                        uiImageScale: image.scale,
                        displayPoints: size,
                        displayPixels: displayPx,
                        interpolation: "high",
                        resizingNote: "aspectFit maxHeight=\(Int(maxDisplayHeight))",
                        fidelityNote: decoded.map {
                            ImageFidelityTrace.compare(sourcePixels: $0, displayPixels: displayPx)
                        }
                    )
                )
            }
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

    private func loadDisplayImage() async {
        guard let reference else {
            displayImage = nil
            didFail = false
            return
        }
        didFail = false
        do {
            // `maxPixelSize: nil` → original public-object bytes (web `/object/public/` path).
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
                // Retina: scale must match the screen or SwiftUI treats pixel dims as 1× points
                // and the bitmap looks soft when composited.
                UIImage(data: data, scale: scale)
            }.value
            guard let decoded else {
                didFail = true
                displayImage = nil
                return
            }
            if ImageFidelityTrace.isEnabled {
                let container = UIScreen.main.bounds.width
                _ = ImageFidelityTrace.probePipeline(
                    label: "aspect-fit/\(purpose.rawValue)",
                    data: data,
                    url: reference.id,
                    httpStatus: nil,
                    decodeScale: scale,
                    containerWidthPoints: container,
                    maxHeightPoints: maxDisplayHeight,
                    screenScale: scale
                )
            }
            displayImage = decoded
        } catch {
            didFail = true
            displayImage = nil
        }
    }
}

private struct AspectFitMediaSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

/// Full-resolution pinch-zoom — loads only when presented.
private struct AspectFitFullImageViewer: View {
    let reference: MediaReference?
    let purpose: ImagePurpose
    let imagePipeline: any ImagePipeline

    @Environment(\.dismiss) private var dismiss
    @State private var zoomScale: CGFloat = 1

    var body: some View {
        NavigationStack {
            ZoomableAsyncImageView(
                reference: reference,
                purpose: purpose,
                imagePipeline: imagePipeline,
                maxPixelSize: nil,
                zoomScale: $zoomScale
            )
            .background(Color.black.ignoresSafeArea())
            .experienceSwipeToDismiss(isEnabled: zoomScale <= 1.02) {
                dismiss()
            }
            .experienceNavigationTitle("Photo")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("detail.media.done")
                }
            }
            .interactiveDismissDisabled(zoomScale > 1.02)
        }
    }
}

/// Tap precedence for detail media — double-tap Like vs single-tap open viewer.
private struct AspectFitMediaTapModifier: ViewModifier {
    var allowsFullResolutionViewer: Bool
    var canOpenViewer: Bool
    var onDoubleTapLike: (() -> Void)?
    var onOpenViewer: () -> Void

    func body(content: Content) -> some View {
        if let onDoubleTapLike {
            content
                .onTapGesture(count: 2, perform: onDoubleTapLike)
                .onTapGesture(count: 1) {
                    guard allowsFullResolutionViewer, canOpenViewer else { return }
                    onOpenViewer()
                }
        } else if allowsFullResolutionViewer {
            content.onTapGesture {
                guard canOpenViewer else { return }
                onOpenViewer()
            }
        } else {
            content
        }
    }
}
