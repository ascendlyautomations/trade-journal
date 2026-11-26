import SwiftUI
import UIKit

struct StoryReplyMessageBubbleView: View {
    private static let storyPreviewWidth: CGFloat = 135

    let payload: StoryReplyMessageSupport.Payload
    let viewerProfileID: ProfileID?
    let isOutgoing: Bool
    let imagePipeline: any ImagePipeline
    var onStoryPreviewTap: (() -> Void)?

    @Environment(\.themeColors) private var colors
    @State private var thumbnail: Image?
    @State private var thumbnailAspectRatio: CGFloat = 9 / 16
    @State private var thumbnailFailed = false

    private var isVideoStory: Bool {
        StoryReplyMessageSupport.isVideoMediaURL(payload.storyImageURL)
    }

    var body: some View {
        let alignment: HorizontalAlignment = isOutgoing ? .trailing : .leading
        VStack(alignment: alignment, spacing: ExperienceSpacing.sm) {
            Text(StoryReplyMessageSupport.contextLabel(payload: payload, viewerProfileID: viewerProfileID))
                .experienceStyle(.caption, color: isOutgoing ? colors.onAccent.opacity(0.92) : colors.secondaryText)
                .fontWeight(.medium)
                .multilineTextAlignment(isOutgoing ? .trailing : .leading)
                .frame(maxWidth: .infinity, alignment: isOutgoing ? .trailing : .leading)

            storyPreview
                .frame(width: Self.storyPreviewWidth)
                .frame(maxWidth: .infinity, alignment: isOutgoing ? .trailing : .leading)

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
                .frame(maxWidth: .infinity, alignment: isOutgoing ? .trailing : .leading)
            }
        }
        .padding(.horizontal, ExperienceSpacing.sm + 2)
        .padding(.vertical, ExperienceSpacing.sm)
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

    @ViewBuilder
    private var storyPreview: some View {
        let content = storyPreviewContent
        Group {
            if let onStoryPreviewTap, !thumbnailFailed {
                Button {
                    ExperienceHaptics.play(.selection)
                    onStoryPreviewTap()
                } label: {
                    content
                }
                .buttonStyle(.experiencePlain)
            } else {
                content
            }
        }
        .accessibilityLabel(storyPreviewAccessibilityLabel)
        .accessibilityHint(thumbnailFailed ? "" : "Opens story")
    }

    private var storyPreviewAccessibilityLabel: String {
        if thumbnailFailed {
            return "Story unavailable"
        }
        return StoryReplyMessageSupport.contextLabel(payload: payload, viewerProfileID: viewerProfileID)
    }

    private var storyPreviewContent: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                .fill(isOutgoing ? Color.white.opacity(0.14) : colors.fillSecondary)

            if thumbnailFailed {
                storyUnavailablePlaceholder
            } else if let thumbnail {
                thumbnail
                    .resizable()
                    .scaledToFill()
            } else {
                progressOrIconPlaceholder
            }

            if isVideoStory, !thumbnailFailed {
                Circle()
                    .fill(Color.black.opacity(0.42))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .offset(x: 1)
                    }
            }
        }
        .aspectRatio(thumbnailAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                .strokeBorder(
                    (isOutgoing ? Color.white : colors.separator).opacity(0.22),
                    lineWidth: 1
                )
        }
    }

    private var storyUnavailablePlaceholder: some View {
        VStack(spacing: ExperienceSpacing.xs) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(isOutgoing ? Color.white.opacity(0.7) : colors.tertiaryText)
            Text("Story unavailable")
                .experienceStyle(.caption2, color: isOutgoing ? Color.white.opacity(0.85) : colors.secondaryText)
                .fontWeight(.medium)
        }
        .padding(ExperienceSpacing.sm)
    }

    @ViewBuilder
    private var progressOrIconPlaceholder: some View {
        if isVideoStory {
            Color.clear
        } else {
            Image(systemName: "photo")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(isOutgoing ? Color.white.opacity(0.65) : colors.tertiaryText)
        }
    }

    private var bubbleMaxWidth: CGFloat {
        UIScreen.main.bounds.width * 0.72
    }

    private func loadThumbnail() async {
        let trimmed = payload.storyImageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            thumbnail = nil
            thumbnailFailed = true
            return
        }
        thumbnailFailed = false
        let reference = MediaReference(
            id: trimmed,
            kind: isVideoStory ? .video : .image,
            altText: nil
        )
        do {
            let data = try await imagePipeline.data(
                for: ImageRequest(
                    reference: reference,
                    purpose: .storyMedia,
                    maxPixelSize: 360
                )
            )
            if let uiImage = UIImage(data: data) {
                let aspect = uiImage.size.height > 0 ? uiImage.size.width / uiImage.size.height : 9 / 16
                thumbnailAspectRatio = min(max(aspect, 0.55), 1.35)
                thumbnail = Image(uiImage: uiImage)
            } else if isVideoStory {
                thumbnail = nil
                thumbnailAspectRatio = 9 / 16
                thumbnailFailed = false
            } else {
                thumbnail = nil
                thumbnailFailed = true
            }
        } catch {
            thumbnail = nil
            thumbnailFailed = !isVideoStory
            if isVideoStory {
                thumbnailAspectRatio = 9 / 16
            }
        }
    }
}