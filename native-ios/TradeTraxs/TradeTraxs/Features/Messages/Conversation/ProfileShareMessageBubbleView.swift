import SwiftUI
import UIKit

struct ProfileShareMessageBubbleView: View {
    let payload: ProfileShareMessageSupport.Payload
    let isOutgoing: Bool
    let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors
    @State private var avatarImage: Image?

    var body: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(ProfileShareMessageSupport.cardTitle(payload: payload))
                    .experienceStyle(
                        .subheadline,
                        color: isOutgoing ? colors.onAccent : colors.primaryText
                    )
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.leading)
                Text("View Profile")
                    .experienceStyle(
                        .caption,
                        color: isOutgoing ? colors.onAccent.opacity(0.9) : colors.accent
                    )
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, ExperienceSpacing.sm + 2)
        .padding(.vertical, ExperienceSpacing.sm)
        .task(id: payload.avatarURL) {
            await loadAvatar()
        }
    }

    @ViewBuilder
    private var avatar: some View {
        Group {
            if let avatarImage {
                avatarImage
                    .resizable()
                    .scaledToFill()
            } else {
                ExperienceAvatar(
                    initials: initials,
                    image: nil,
                    size: 48
                )
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(
                    (isOutgoing ? Color.white : colors.separator).opacity(0.18),
                    lineWidth: 1
                )
        }
        .accessibilityHidden(true)
    }

    private var initials: String {
        let source = payload.displayName ?? payload.username ?? "T"
        return String(source.prefix(1)).uppercased()
    }

    private func loadAvatar() async {
        guard let url = payload.avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !url.isEmpty
        else {
            avatarImage = nil
            return
        }
        let reference = MediaReference(id: url, kind: .image, altText: nil)
        do {
            let data = try await imagePipeline.data(
                for: ImageRequest(
                    reference: reference,
                    purpose: .profileAvatar,
                    maxPixelSize: 120
                )
            )
            if let uiImage = UIImage(data: data) {
                avatarImage = Image(uiImage: uiImage)
            } else {
                avatarImage = nil
            }
        } catch {
            avatarImage = nil
        }
    }
}
