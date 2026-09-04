import SwiftUI
import UIKit

struct StoryShareMessageBubbleView: View {
    let payload: StoryShareMessageSupport.Payload
    let isOutgoing: Bool
    let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors
    @State private var thumbnail: Image?

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack(spacing: ExperienceSpacing.sm) {
                storyThumbnail
                VStack(alignment: .leading, spacing: 2) {
                    Text(StoryShareMessageSupport.cardTitle(payload: payload))
                        .experienceStyle(
                            .subheadline,
                            color: isOutgoing ? colors.onAccent : colors.primaryText
                        )
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.leading)
                    Text("View Story")
                        .experienceStyle(
                            .caption,
                            color: isOutgoing ? colors.onAccent.opacity(0.82) : colors.accent
                        )
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, ExperienceSpacing.sm + 2)
        .padding(.vertical, ExperienceSpacing.sm)
        .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
        .background(
            isOutgoing ? colors.accent : colors.incomingMessageBubble,
            in: RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
        )
        .accessibilityIdentifier(
            isOutgoing ? "conversation.bubble.storyShare.outgoing" : "conversation.bubble.storyShare.incoming"
        )
        .task(id: payload.storyImageURL) {
            await loadThumbnail()
        }
    }

    @ViewBuilder
    private var storyThumbnail: some View {
        Group {
            if let thumbnail {
                thumbnail
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                    .fill(isOutgoing ? Color.white.opacity(0.16) : colors.fillSecondary)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(isOutgoing ? Color.white.opacity(0.72) : colors.tertiaryText)
                    }
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                .strokeBorder(
                    (isOutgoing ? Color.white : colors.separator).opacity(0.18),
                    lineWidth: 1
                )
        }
        .accessibilityHidden(true)
    }

    private var bubbleMaxWidth: CGFloat {
        min(280, UIScreen.main.bounds.width * 0.72)
    }

    private func loadThumbnail() async {
        let trimmed = payload.storyImageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            thumbnail = nil
            return
        }
        let reference = MediaReference(id: trimmed, kind: .image, altText: nil)
        do {
            let data = try await imagePipeline.data(
                for: ImageRequest(
                    reference: reference,
                    purpose: .storyMedia,
                    maxPixelSize: 120
                )
            )
            if let uiImage = UIImage(data: data) {
                thumbnail = Image(uiImage: uiImage)
            } else {
                thumbnail = nil
            }
        } catch {
            thumbnail = nil
        }
    }
}
