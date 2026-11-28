import SwiftUI
import UIKit

struct StoryReplyMessageBubbleView: View {
    let payload: StoryReplyMessageSupport.Payload
    let viewerProfileID: ProfileID?
    let isOutgoing: Bool
    let imagePipeline: any ImagePipeline
    let storage: any ObjectStorageProviding
    let feed: any FeedRepository
    var onStoryPreviewTap: (() -> Void)?

    @Environment(\.themeColors) private var colors
    @State private var thumbnail: Image?
    @State private var mediaAllowed = false
    @State private var accessChecked = false
    @State private var mediaLoadFailed = false

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
        .task(id: payload.storyID) {
            if applyCachedPreviewIfAvailable() { return }
            await resolveMediaAccess()
        }
    }

    @ViewBuilder
    private var storyPreview: some View {
        let slot = storyPreviewSlot
        Group {
            if canOpenStoryPreview, let onStoryPreviewTap {
                Button {
                    ExperienceHaptics.play(.selection)
                    onStoryPreviewTap()
                } label: {
                    slot
                }
                .buttonStyle(.experiencePlain)
            } else {
                slot
            }
        }
        .accessibilityLabel(StoryReplyMessageSupport.contextLabel(payload: payload, viewerProfileID: viewerProfileID))
        .accessibilityHint(canOpenStoryPreview ? "Opens story" : "")
    }

    private var canOpenStoryPreview: Bool {
        accessChecked && mediaAllowed && !mediaLoadFailed && thumbnail != nil
    }

    private var storyPreviewSlot: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                .fill(isOutgoing ? Color.white.opacity(0.14) : colors.fillSecondary)

            if canOpenStoryPreview, let thumbnail {
                thumbnail
                    .resizable()
                    .scaledToFill()
            }

            if !accessChecked || (mediaAllowed && thumbnail == nil && !mediaLoadFailed) {
                ExperienceIndeterminateProgress(controlSize: .small)
            }

            if accessChecked && (!mediaAllowed || mediaLoadFailed) {
                unavailableLabel
            }

            if canOpenStoryPreview, isVideoStory {
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
        .frame(
            width: ConversationStoryBubblePreviewPolicy.replyPreviewWidth,
            height: ConversationStoryBubblePreviewPolicy.replyPreviewHeight
        )
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                .strokeBorder(
                    (isOutgoing ? Color.white : colors.separator).opacity(0.22),
                    lineWidth: 1
                )
        }
        .clipped()
    }

    private var unavailableLabel: some View {
        VStack(spacing: ExperienceSpacing.xs) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(isOutgoing ? Color.white.opacity(0.75) : colors.tertiaryText)
            Text(ConversationStoryBubblePreviewPolicy.unavailableLabel)
                .experienceStyle(.caption, color: isOutgoing ? Color.white.opacity(0.9) : colors.secondaryText)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, ExperienceSpacing.sm)
    }

    private var bubbleMaxWidth: CGFloat {
        UIScreen.main.bounds.width * 0.72
    }

    private func applyCachedPreviewIfAvailable() -> Bool {
        guard let cached = ConversationStoryDmReplyPreviewCache.snapshot(storyID: payload.storyID) else {
            return false
        }
        accessChecked = cached.accessChecked
        mediaAllowed = cached.mediaAllowed
        mediaLoadFailed = cached.mediaLoadFailed
        if let uiImage = cached.thumbnail {
            thumbnail = Image(uiImage: uiImage)
        } else {
            thumbnail = nil
        }
        return true
    }

    private func resolveMediaAccess() async {
        let access = await ConversationStoryDmPreviewLoader.resolveAccess(
            storyID: payload.storyID,
            feed: feed
        )

        guard let access else {
            mediaAllowed = false
            mediaLoadFailed = true
            accessChecked = true
            storePreviewCache(thumbnailImage: nil)
            return
        }

        guard access.allowed else {
            mediaAllowed = false
            mediaLoadFailed = true
            accessChecked = true
            storePreviewCache(thumbnailImage: nil)
            return
        }

        mediaAllowed = true
        let loaded = await ConversationStoryDmPreviewLoader.loadThumbnailUIImage(
            imagePipeline: imagePipeline,
            storage: storage,
            access: access,
            fallbackImageURL: payload.storyImageURL,
            isVideo: isVideoStory,
            maxPixelSize: 360
        )

        if let uiImage = loaded.image {
            thumbnail = Image(uiImage: uiImage)
            mediaLoadFailed = false
        } else {
            thumbnail = nil
            mediaLoadFailed = true
        }
        accessChecked = true
        storePreviewCache(thumbnailImage: loaded.image)
    }

    private func storePreviewCache(thumbnailImage: UIImage?) {
        ConversationStoryDmReplyPreviewCache.store(
            storyID: payload.storyID,
            ConversationStoryDmReplyPreviewCache.Snapshot(
                accessChecked: accessChecked,
                mediaAllowed: mediaAllowed,
                mediaLoadFailed: mediaLoadFailed,
                thumbnail: thumbnailImage
            )
        )
    }
}