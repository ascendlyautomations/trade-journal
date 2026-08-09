import SwiftUI
import UIKit

/// Shared aspect-fit media for Post / Trade — Instagram-style natural proportions.
///
/// Root layout contract:
/// 1. Read the decoded image’s pixel aspect ratio
/// 2. Size the container with that ratio (width-driven)
/// 3. Cap height only for extreme portrait media
/// 4. Never use `scaledToFill` / never clip the bitmap
struct AspectFitMediaView: View {
    let reference: MediaReference?
    let purpose: ImagePurpose
    let imagePipeline: any ImagePipeline
    var accessibilityIdentifier: String = "detail.media"
    var emptyIcon: AppIcon = .photo
    /// When `false`, tap does not open the full-resolution viewer (list previews).
    var allowsFullResolutionViewer: Bool = true

    @Environment(\.themeColors) private var colors
    @State private var displayImage: UIImage?
    @State private var didFail = false
    @State private var showsFullViewer = false

    private var displayMaxPixelSize: Int {
        let width = UIScreen.main.bounds.width * UIScreen.main.scale
        return max(720, Int(width.rounded()))
    }

    /// Soft cap for very tall portrait uploads (Instagram-style feed).
    private var maxDisplayHeight: CGFloat {
        min(UIScreen.main.bounds.height * 0.58, 720)
    }

    var body: some View {
        Group {
            if let displayImage {
                media(displayImage)
            } else if didFail || reference == nil {
                placeholder
            } else {
                loading
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            guard allowsFullResolutionViewer, reference != nil, displayImage != nil else { return }
            ExperienceHaptics.play(.selection)
            showsFullViewer = true
        }
        .task(id: "\(reference?.id ?? "")|\(purpose.rawValue)") {
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
        let aspect = max(image.size.width, 1) / max(image.size.height, 1)
        return Image(uiImage: image)
            .resizable()
            // Explicit ratio + fit → natural portrait / landscape / square.
            .aspectRatio(aspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: maxDisplayHeight)
            .background(colors.fillPrimary)
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

    private func loadDisplayImage() async {
        guard let reference else {
            displayImage = nil
            didFail = false
            return
        }
        didFail = false
        do {
            let data = try await imagePipeline.data(
                for: ImageRequest(
                    reference: reference,
                    purpose: purpose,
                    maxPixelSize: displayMaxPixelSize,
                    allowsProgressiveLoading: true
                )
            )
            let decoded = await Task.detached(priority: .userInitiated) {
                UIImage(data: data)
            }.value
            guard let decoded else {
                didFail = true
                displayImage = nil
                return
            }
            displayImage = decoded
        } catch {
            didFail = true
            displayImage = nil
        }
    }
}

/// Full-resolution pinch-zoom — loads only when presented.
private struct AspectFitFullImageViewer: View {
    let reference: MediaReference?
    let purpose: ImagePurpose
    let imagePipeline: any ImagePipeline

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZoomableAsyncImageView(
                reference: reference,
                purpose: purpose,
                imagePipeline: imagePipeline,
                maxPixelSize: nil
            )
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("detail.media.done")
                }
            }
        }
    }
}
