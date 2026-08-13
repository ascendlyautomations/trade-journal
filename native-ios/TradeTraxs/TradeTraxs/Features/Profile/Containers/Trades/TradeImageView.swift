import SwiftUI
import UIKit

/// Compact list thumbnail via ``ImagePipeline``.
///
/// Default is **aspect-fit** inside the square slot so user uploads are not
/// arbitrarily cropped. Use ``ContentMode.fill`` only when a deliberate crop
/// is required (e.g. video poster tiles).
struct TradeImageView: View {
    let reference: MediaReference?
    let imagePipeline: any ImagePipeline
    var purpose: ImagePurpose = .tradeScreenshot
    var contentMode: ContentMode = .fit
    var side: CGFloat = 96
    /// Optional override — journal cards use a wide compact strip.
    var width: CGFloat? = nil
    var height: CGFloat? = nil

    @Environment(\.themeColors) private var colors
    @State private var image: Image?
    @State private var didFail = false

    private var resolvedWidth: CGFloat { width ?? side }
    private var resolvedHeight: CGFloat { height ?? side }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                .fill(colors.fillPrimary)

            if let image {
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if didFail || reference == nil {
                ExperienceIcon(
                    icon: purpose == .postImage || purpose == .reelThumbnail ? .photo : .chart,
                    size: .lg,
                    color: colors.tertiaryText
                )
            } else {
                ExperienceSkeleton(height: resolvedHeight, cornerRadius: ExperienceRadius.md)
            }
        }
        .frame(width: resolvedWidth, height: resolvedHeight)
        // Clip only rounds the container — with `.fit` the bitmap itself is not cropped.
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
        .task(id: "\(reference?.id ?? "")|\(purpose.rawValue)|\(Int(resolvedWidth))x\(Int(resolvedHeight))|\(contentMode == .fill)") {
            await load()
        }
    }

    private func load() async {
        guard let reference else {
            image = nil
            didFail = false
            return
        }
        didFail = false
        let pixelBudget = max(128, Int(max(resolvedWidth, resolvedHeight) * UIScreen.main.scale * 2))
        do {
            let data = try await imagePipeline.data(
                for: ImageRequest(
                    reference: reference,
                    purpose: purpose,
                    maxPixelSize: pixelBudget
                )
            )
            let decoded = await Task.detached(priority: .utility) {
                UIImage(data: data)
            }.value
            guard let decoded else {
                didFail = true
                image = nil
                return
            }
            image = Image(uiImage: decoded)
        } catch {
            didFail = true
            image = nil
        }
    }
}
