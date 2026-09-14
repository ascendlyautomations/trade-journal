import SwiftUI
import UIKit

/// Fixed-size rounded-square profile thumbnail for Explore trader surfaces.
/// Uses the shared image pipeline; does not let the source image aspect ratio affect layout.
struct ExploreProfileAvatarView: View {
    let profile: Profile
    let imagePipeline: any ImagePipeline
    var size: CGFloat = 48

    @State private var displayImage: UIImage?

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var initials: String {
        ProfileDisplay.initials(
            displayName: profile.displayName,
            username: profile.username
        )
    }

    private var cornerRadius: CGFloat {
        ExperienceRadius.sm
    }

    private var clipShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        ZStack {
            clipShape
                .fill(colors.fillPrimary)

            Text(initials)
                .experienceStyle(.caption, color: colors.secondaryText)
                .opacity(displayImage == nil ? 1 : 0)

            if let displayImage {
                Image(uiImage: displayImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .transition(reduceMotion ? .identity : .opacity)
            }
        }
        .frame(width: size, height: size)
        .clipShape(clipShape)
        .overlay {
            clipShape.stroke(colors.border, lineWidth: ExperienceBorder.hairline)
        }
        .fixedSize()
        .animation(
            ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
            value: displayImage == nil
        )
        .task(id: profile.avatar?.id) {
            await load()
        }
        .accessibilityLabel(Text(initials.isEmpty ? "Avatar" : initials))
        .accessibilityIdentifier("explore.profile.avatar.\(profile.id.rawValue)")
    }

    private func load() async {
        guard let reference = profile.avatar else {
            displayImage = nil
            return
        }
        do {
            let data = try await imagePipeline.data(
                for: ImageRequest(
                    reference: reference,
                    purpose: .profileAvatar,
                    maxPixelSize: 128
                )
            )
            if let ui = UIImage(data: data) {
                displayImage = MediaImageOrientation.normalized(ui)
            } else {
                displayImage = nil
            }
        } catch {
            displayImage = nil
        }
    }
}
