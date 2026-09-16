import SwiftUI
import UIKit

/// Fixed-size circular profile thumbnail for Explore — same pipeline/presentation as ``TradeRoomCircularAvatar``.
struct ExploreProfileAvatarView: View {
    let profile: Profile
    let imagePipeline: any ImagePipeline
    var diameter: CGFloat = 52

    @Environment(\.themeColors) private var colors
    @State private var avatarImage: Image?

    private var initials: String {
        ProfileDisplay.initials(
            displayName: profile.displayName,
            username: profile.username
        )
    }

    var body: some View {
        Group {
            if let avatarImage {
                avatarImage
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    colors.fillSecondary
                    Text(initials)
                        .experienceStyle(.caption, color: colors.secondaryText)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(colors.border.opacity(0.35), lineWidth: 0.5)
        )
        .task(id: profile.avatar?.id) {
            await loadAvatar()
        }
        .accessibilityLabel(Text(initials.isEmpty ? "Avatar" : initials))
        .accessibilityIdentifier("explore.profile.avatar.\(profile.id.rawValue)")
    }

    private func loadAvatar() async {
        guard let reference = profile.avatar else {
            avatarImage = nil
            return
        }
        do {
            let data = try await imagePipeline.data(
                for: ImageRequest(
                    reference: reference,
                    purpose: .profileAvatar,
                    maxPixelSize: max(96, Int(diameter * 3))
                )
            )
            if let ui = UIImage(data: data) {
                avatarImage = Image(uiImage: MediaImageOrientation.normalized(ui))
            } else {
                avatarImage = nil
            }
        } catch {
            avatarImage = nil
        }
    }
}
