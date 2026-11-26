import SwiftUI
import UIKit

/// Group conversation avatar — remote image or default `person.3` glyph (web `group-default.png` parity).
struct GroupConversationAvatarView: View {
    let avatar: MediaReference?
    let imagePipeline: any ImagePipeline
    var size: CGFloat = MessagesInboxLayout.avatarSide

    @Environment(\.themeColors) private var colors
    @State private var loadedImage: Image?

    var body: some View {
        ZStack {
            if let loadedImage {
                loadedImage
                    .resizable()
                    .scaledToFill()
            } else if avatar != nil {
                Circle()
                    .fill(colors.backgroundSecondary)
            } else {
                Circle()
                    .fill(colors.backgroundSecondary)
                Image(systemName: AppIcon.rooms.rawValue)
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(colors.secondaryText)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(colors.border.opacity(0.35), lineWidth: ExperienceBorder.hairline))
        .task(id: avatar?.id) {
            await load()
        }
        .accessibilityHidden(true)
    }

    private func load() async {
        guard let avatar else {
            loadedImage = nil
            return
        }
        do {
            let data = try await imagePipeline.data(
                for: ImageRequest(
                    reference: avatar,
                    purpose: .profileAvatar,
                    maxPixelSize: Int(size * 3)
                )
            )
            if let ui = UIImage(data: data) {
                loadedImage = Image(uiImage: ui)
            } else {
                loadedImage = nil
            }
        } catch {
            loadedImage = nil
        }
    }
}