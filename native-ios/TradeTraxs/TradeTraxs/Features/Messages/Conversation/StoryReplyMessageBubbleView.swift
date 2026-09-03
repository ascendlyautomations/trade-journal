import SwiftUI
import UIKit

struct StoryReplyMessageBubbleView: View {
    let payload: StoryReplyMessageSupport.Payload
    let viewerProfileID: ProfileID?
    let isOutgoing: Bool
    let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors
    @State private var thumbnail: Image?

    var body: some View {
        let alignment: HorizontalAlignment = isOutgoing ? .trailing : .leading
        VStack(alignment: alignment, spacing: 0) {
            storyPreviewHeader
            if let replyText = StoryReplyMessageSupport.replyText(from: payload) {
                ConversationMessageTextLayout(
                    maxWidth: bubbleMaxWidth,
                    horizontalAlignment: alignment
                ) {
                    Text(replyText)
                        .experienceStyle(
                            .body,
                            color: isOutgoing ? colors.onAccent : colors.primaryText
                        )
                        .multilineTextAlignment(isOutgoing ? .trailing : .leading)
                }
                .padding(.horizontal, ExperienceSpacing.sm + 2)
                .padding(.top, ExperienceSpacing.sm)
                .padding(.bottom, ExperienceSpacing.sm)
            }
        }
        .frame(maxWidth: bubbleMaxWidth, alignment: Alignment(horizontal: alignment, vertical: .top))
        .background(
            isOutgoing ? colors.accent : colors.incomingMessageBubble,
            in: RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
        )
        .accessibilityIdentifier(
            isOutgoing ? "conversation.bubble.storyReply.outgoing" : "conversation.bubble.storyReply.incoming"
        )
        .task(id: payload.storyImageURL) {
            await loadThumbnail()
        }
    }

    private var storyPreviewHeader: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            storyThumbnail
            Text(StoryReplyMessageSupport.contextLabel(payload: payload, viewerProfileID: viewerProfileID))
                .experienceStyle(.caption, color: isOutgoing ? colors.onAccent.opacity(0.88) : colors.secondaryText)
                .fontWeight(.medium)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, ExperienceSpacing.sm + 2)
        .padding(.vertical, ExperienceSpacing.sm)
        .overlay(alignment: .bottom) {
            Divider()
                .overlay((isOutgoing ? Color.white : colors.separator).opacity(0.18))
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
        .frame(width: 40, height: 40)
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
        UIScreen.main.bounds.width * 0.72
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
