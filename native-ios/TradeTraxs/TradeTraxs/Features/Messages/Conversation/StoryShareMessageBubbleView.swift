import SwiftUI
import UIKit

struct StoryShareMessageBubbleView: View {
    let payload: StoryShareMessageSupport.Payload
    let isOutgoing: Bool
    let imagePipeline: any ImagePipeline
    var feed: (any FeedRepository)?
    var storage: (any ObjectStorageProviding)?

    @Environment(\.themeColors) private var colors
    @State private var thumbnail: Image?
    @State private var accessChecked = false
    @State private var mediaAllowed = true
    @State private var mediaLoadFailed = false

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
                    Text(mediaAllowed && !mediaLoadFailed ? "View Story" : ConversationStoryBubblePreviewPolicy.unavailableLabel)
                        .experienceStyle(
                            .caption,
                            color: storySubtitleColor
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
        .task(id: payload.storyID) {
            await resolvePreview()
        }
    }

    @ViewBuilder
    private var storyThumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                .fill(isOutgoing ? Color.white.opacity(0.16) : colors.fillSecondary)

            if !accessChecked {
                ExperienceIndeterminateProgress(controlSize: .small)
            } else if let thumbnail {
                thumbnail
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: mediaAllowed && !mediaLoadFailed ? "photo" : "photo.on.rectangle.angled")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isOutgoing ? Color.white.opacity(0.72) : colors.tertiaryText)
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

    private var storySubtitleColor: Color {
        if mediaAllowed, !mediaLoadFailed {
            return isOutgoing ? colors.onAccent.opacity(0.9) : colors.accent
        }
        return isOutgoing ? Color.white.opacity(0.85) : colors.secondaryText
    }

    private func resolvePreview() async {
        accessChecked = false
        mediaAllowed = true
        mediaLoadFailed = false
        thumbnail = nil

        if let feed, let storage {
            let access = await ConversationStoryDmPreviewLoader.resolveAccess(
                storyID: payload.storyID,
                feed: feed
            )
            guard let access else {
                mediaAllowed = false
                accessChecked = true
                return
            }
            mediaAllowed = access.allowed
            guard access.allowed else {
                accessChecked = true
                return
            }
            let isVideo = StoryReplyMessageSupport.isVideoMediaURL(
                access.imageURL ?? payload.storyImageURL
            )
            let loaded = await ConversationStoryDmPreviewLoader.loadThumbnailUIImage(
                imagePipeline: imagePipeline,
                storage: storage,
                access: access,
                fallbackImageURL: payload.storyImageURL,
                isVideo: isVideo,
                maxPixelSize: 120
            )
            if let uiImage = loaded.image {
                thumbnail = Image(uiImage: uiImage)
            } else {
                mediaLoadFailed = true
            }
            accessChecked = true
            return
        }

        await loadLegacyThumbnail()
        accessChecked = true
    }

    private func loadLegacyThumbnail() async {
        let trimmed = payload.storyImageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            mediaLoadFailed = true
            return
        }
        let reference = MediaReference(id: trimmed, kind: .image, altText: nil)
        for attempt in 1...ConversationStoryBubblePreviewPolicy.maxMediaAttempts {
            do {
                let resolved = await StorySignedMediaResolver.shared.resolvedPlaybackReference(reference)
                let data = try await imagePipeline.data(
                    for: ImageRequest(
                        reference: resolved,
                        purpose: .storyMedia,
                        maxPixelSize: 120
                    )
                )
                if let uiImage = UIImage(data: data) {
                    thumbnail = Image(uiImage: uiImage)
                    return
                }
            } catch {}
            guard attempt < ConversationStoryBubblePreviewPolicy.maxMediaAttempts else { break }
            try? await Task.sleep(nanoseconds: ConversationStoryBubblePreviewPolicy.retryDelayNs)
        }
        mediaLoadFailed = true
    }
}