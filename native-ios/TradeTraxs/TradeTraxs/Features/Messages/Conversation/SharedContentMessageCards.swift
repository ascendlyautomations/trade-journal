import SwiftUI

struct SharedContentUnavailableCard: View {
    let title: String
    var isOutgoing: Bool
    var includesBackground: Bool = true

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: "eye.slash")
                    .font(.caption.weight(.semibold))
                Text(title)
                    .experienceStyle(.caption, color: tertiaryTextColor)
            }
            Text("This content is unavailable.")
                .experienceStyle(.subheadline, color: secondaryTextColor)
        }
        .padding(.horizontal, includesBackground ? ExperienceSpacing.sm + 2 : 0)
        .padding(.vertical, includesBackground ? ExperienceSpacing.sm : 0)
        .frame(
            maxWidth: includesBackground
                ? ConversationBubbleMediaLayout.sharedCardBubbleMaxWidth
                : .infinity,
            alignment: .leading
        )
        .background {
            if includesBackground {
                RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
                    .fill(isOutgoing ? colors.accent : colors.incomingMessageBubble)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). Content unavailable.")
    }

    private var secondaryTextColor: Color {
        isOutgoing ? colors.onAccent.opacity(0.88) : colors.secondaryText
    }

    private var tertiaryTextColor: Color {
        isOutgoing ? colors.onAccent.opacity(0.78) : colors.tertiaryText
    }
}

struct SharedPostMessageCard: View {
    let post: Post?
    let imagePipeline: any ImagePipeline
    var isOutgoing: Bool
    var includesBackground: Bool = true
    var headerTitle: String = "Shared a post"
    var mediaLayoutWidth: CGFloat? = nil

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            sharedHeader

            if let post {
                if let media = post.media.first(where: { !$0.id.isEmpty }) {
                    AspectFitMediaView(
                        reference: media,
                        purpose: .postImage,
                        imagePipeline: imagePipeline,
                        allowsFullResolutionViewer: false,
                        layoutWidth: mediaLayoutWidth
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                    )
                }

                let caption = post.body.trimmingCharacters(in: .whitespacesAndNewlines)
                if !caption.isEmpty {
                    Text(truncated(caption))
                        .experienceStyle(.body, color: secondaryTextColor)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
            } else {
                loadingPlaceholder(label: "Loading post…")
            }
        }
        .padding(.horizontal, includesBackground ? ExperienceSpacing.sm + 2 : 0)
        .padding(.vertical, includesBackground ? ExperienceSpacing.sm : 0)
        .frame(
            maxWidth: includesBackground
                ? ConversationBubbleMediaLayout.sharedCardBubbleMaxWidth
                : .infinity,
            alignment: .leading
        )
        .background {
            if includesBackground {
                RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
                    .fill(isOutgoing ? colors.accent : colors.incomingMessageBubble)
            }
        }
        .accessibilityIdentifier("conversation.bubble.sharedPost")
    }

    private var sharedHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text.image")
                .font(.caption.weight(.semibold))
            Text(headerTitle)
                .experienceStyle(.caption, color: tertiaryTextColor)
        }
    }

    private var secondaryTextColor: Color {
        isOutgoing ? colors.onAccent.opacity(0.88) : colors.secondaryText
    }

    private var tertiaryTextColor: Color {
        isOutgoing ? colors.onAccent.opacity(0.78) : colors.tertiaryText
    }

    private func truncated(_ value: String) -> String {
        guard value.count > 140 else { return value }
        return String(value.prefix(140)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private func loadingPlaceholder(label: String) -> some View {
        SharedContentMessageCardLoadingPlaceholder(
            label: label,
            isOutgoing: isOutgoing,
            mediaLayoutWidth: mediaLayoutWidth
        )
    }
}

struct SharedReelMessageCard: View {
    let reel: Reel?
    let author: Profile?
    let imagePipeline: any ImagePipeline
    var isOutgoing: Bool
    var includesBackground: Bool = true
    var mediaLayoutWidth: CGFloat? = nil

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: "play.rectangle")
                    .font(.caption.weight(.semibold))
                Text("Shared a clip")
                    .experienceStyle(.caption, color: tertiaryTextColor)
            }

            if let reel {
                ZStack {
                    AspectFitMediaView(
                        reference: reel.thumbnail ?? reel.video,
                        purpose: .reelThumbnail,
                        imagePipeline: imagePipeline,
                        allowsFullResolutionViewer: false,
                        layoutWidth: mediaLayoutWidth
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                    )

                    Image(systemName: "play.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                }

                if let author {
                    HStack(spacing: 4) {
                        Text(author.displayName)
                            .experienceStyle(.caption, color: secondaryTextColor)
                            .lineLimit(1)
                    }
                }

                if let caption = reel.caption?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !caption.isEmpty
                {
                    Text(caption)
                        .experienceStyle(.body, color: secondaryTextColor)
                        .lineLimit(2)
                }
            } else {
                loadingPlaceholder(label: "Loading clip…")
            }
        }
        .padding(.horizontal, includesBackground ? ExperienceSpacing.sm + 2 : 0)
        .padding(.vertical, includesBackground ? ExperienceSpacing.sm : 0)
        .frame(
            maxWidth: includesBackground
                ? ConversationBubbleMediaLayout.sharedCardBubbleMaxWidth
                : .infinity,
            alignment: .leading
        )
        .background {
            if includesBackground {
                RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
                    .fill(isOutgoing ? colors.accent : colors.incomingMessageBubble)
            }
        }
        .accessibilityIdentifier("conversation.bubble.sharedReel")
    }

    private var secondaryTextColor: Color {
        isOutgoing ? colors.onAccent.opacity(0.88) : colors.secondaryText
    }

    private var tertiaryTextColor: Color {
        isOutgoing ? colors.onAccent.opacity(0.78) : colors.tertiaryText
    }

    private func loadingPlaceholder(label: String) -> some View {
        SharedContentMessageCardLoadingPlaceholder(
            label: label,
            isOutgoing: isOutgoing,
            mediaLayoutWidth: mediaLayoutWidth
        )
    }
}

struct SharedAchievementMessageCard: View {
    let achievement: Achievement?
    let author: Profile?
    let imagePipeline: any ImagePipeline
    var isOutgoing: Bool
    var includesBackground: Bool = true
    var mediaLayoutWidth: CGFloat? = nil

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: "trophy")
                    .font(.caption.weight(.semibold))
                Text("Shared an achievement")
                    .experienceStyle(.caption, color: tertiaryTextColor)
            }

            if let achievement {
                if let image = achievement.image {
                    AspectFitMediaView(
                        reference: image,
                        purpose: .postImage,
                        imagePipeline: imagePipeline,
                        allowsFullResolutionViewer: false,
                        layoutWidth: mediaLayoutWidth
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                    )
                }

                Text(achievement.title)
                    .experienceStyle(.headline, color: isOutgoing ? colors.onAccent : colors.primaryText)
                    .lineLimit(2)

                if let author {
                    HStack(spacing: 4) {
                        Text(author.displayName)
                            .experienceStyle(.caption, color: secondaryTextColor)
                            .lineLimit(1)
                    }
                }

                if let details = achievement.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !details.isEmpty
                {
                    Text(details)
                        .experienceStyle(.caption, color: secondaryTextColor)
                        .lineLimit(2)
                }
            } else {
                loadingPlaceholder(label: "Loading achievement…")
            }
        }
        .padding(.horizontal, includesBackground ? ExperienceSpacing.sm + 2 : 0)
        .padding(.vertical, includesBackground ? ExperienceSpacing.sm : 0)
        .frame(
            maxWidth: includesBackground
                ? ConversationBubbleMediaLayout.sharedCardBubbleMaxWidth
                : .infinity,
            alignment: .leading
        )
        .background {
            if includesBackground {
                RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
                    .fill(isOutgoing ? colors.accent : colors.incomingMessageBubble)
            }
        }
        .accessibilityIdentifier("conversation.bubble.sharedAchievement")
    }

    private var secondaryTextColor: Color {
        isOutgoing ? colors.onAccent.opacity(0.88) : colors.secondaryText
    }

    private var tertiaryTextColor: Color {
        isOutgoing ? colors.onAccent.opacity(0.78) : colors.tertiaryText
    }

    private func loadingPlaceholder(label: String) -> some View {
        SharedContentMessageCardLoadingPlaceholder(
            label: label,
            isOutgoing: isOutgoing,
            mediaLayoutWidth: mediaLayoutWidth
        )
    }
}

/// Reserves inline media height while shared entities hydrate so scroll layout stays stable.
struct SharedContentMessageCardLoadingPlaceholder: View {
    let label: String
    var isOutgoing: Bool
    var mediaLayoutWidth: CGFloat? = nil

    @Environment(\.themeColors) private var colors

    private var placeholderMediaHeight: CGFloat {
        guard let mediaLayoutWidth else { return 120 }
        let maxHeight = min(UIScreen.main.bounds.height * 0.58, 720)
        return ImageFidelityTrace.placeholderRowHeight(
            containerWidthPoints: mediaLayoutWidth,
            maxHeightPoints: maxHeight
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                .fill(isOutgoing ? colors.onAccent.opacity(0.12) : colors.fillPrimary)
                .frame(width: mediaLayoutWidth, height: placeholderMediaHeight)
                .frame(maxWidth: mediaLayoutWidth == nil ? .infinity : nil)
            Text(label)
                .experienceStyle(.subheadline, color: isOutgoing ? colors.onAccent.opacity(0.88) : colors.secondaryText)
        }
    }
}
