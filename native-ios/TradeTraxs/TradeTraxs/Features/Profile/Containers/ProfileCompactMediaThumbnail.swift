import SwiftUI
import UIKit

/// Compact Profile card thumbnail sizing — container hugs the final cropped image aspect ratio.
enum ProfileCompactThumbnailLayout {
    static let width: CGFloat = 96
    static let placeholderHeight: CGFloat = 96
    static let minimumHeight: CGFloat = 36

    /// Portrait previews cap at the Feed 4:5 maximum so legacy tall images stay compact.
    static var maximumPortraitHeight: CGFloat {
        width / FeedMediaLayout.minimumFeedAspectRatio
    }

    static func containerSize(forImageAspect imageAspect: CGFloat) -> CGSize {
        let safeAspect = max(imageAspect, 0.01)
        var height = width / safeAspect
        height = min(height, maximumPortraitHeight)
        height = max(height, minimumHeight)
        return CGSize(width: width, height: height)
    }
}

/// Left-side Profile browse thumbnail — width fixed, height derived from loaded image pixels.
struct ProfileCompactMediaThumbnail: View {
    let reference: MediaReference?
    let purpose: ImagePurpose
    let imagePipeline: any ImagePipeline

    @Environment(\.displayScale) private var displayScale
    @Environment(\.themeColors) private var colors
    @State private var displayImage: UIImage?

    init(reference: MediaReference?, purpose: ImagePurpose, imagePipeline: any ImagePipeline) {
        self.reference = reference
        self.purpose = purpose
        self.imagePipeline = imagePipeline
        if let reference {
            _displayImage = State(
                initialValue: ProfileBrowseMediaDisplayCache.uiImage(
                    reference: reference,
                    purpose: purpose
                )
            )
        } else {
            _displayImage = State(initialValue: nil)
        }
    }

    private var containerSize: CGSize {
        if let displayImage {
            let aspect = MediaImageOrientation.aspectRatio(of: displayImage)
            return ProfileCompactThumbnailLayout.containerSize(forImageAspect: aspect)
        }
        return CGSize(
            width: ProfileCompactThumbnailLayout.width,
            height: ProfileCompactThumbnailLayout.placeholderHeight
        )
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                .fill(displayImage == nil ? colors.fillPrimary : Color.clear)

            if let displayImage {
                Image(uiImage: displayImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(
                        MediaImageOrientation.aspectRatio(of: displayImage),
                        contentMode: .fit
                    )
                    .frame(width: containerSize.width, height: containerSize.height)
            } else if reference == nil {
                ExperienceIcon(
                    icon: purpose == .postImage ? .photo : .chart,
                    size: .lg,
                    color: colors.tertiaryText
                )
            } else {
                ExperienceSkeleton(
                    height: containerSize.height,
                    cornerRadius: ExperienceRadius.md
                )
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
        .animation(.easeOut(duration: 0.15), value: containerSize.height)
        .task(id: loadTaskID) {
            await loadDisplayImage()
        }
    }

    private var loadTaskID: String {
        guard let reference else { return "" }
        return ProfileBrowseMediaDisplayCache.cacheKey(reference: reference, purpose: purpose)
    }

    private func loadDisplayImage() async {
        guard let reference else {
            displayImage = nil
            return
        }
        if displayImage != nil { return }
        let pixelBudget = ProfileBrowseMediaLoader.listPixelBudget(displayScale: displayScale)
        let loaded = await ProfileBrowseMediaLoader.loadUIImage(
            reference: reference,
            purpose: purpose,
            maxPixelSize: pixelBudget,
            displayScale: displayScale,
            imagePipeline: imagePipeline,
            existing: displayImage
        )
        displayImage = loaded
    }
}

/// Compact Profile card media row — height is max(thumbnail, metadata); thumbnail centers vertically in that region.
struct ProfileCompactCardMediaSection<Thumbnail: View, Metadata: View>: View {
    var spacing: CGFloat = ExperienceSpacing.md
    @ViewBuilder let thumbnail: () -> Thumbnail
    @ViewBuilder let metadata: () -> Metadata

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                thumbnail()
                Spacer(minLength: 0)
            }
            .frame(width: ProfileCompactThumbnailLayout.width)

            metadata()
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}
