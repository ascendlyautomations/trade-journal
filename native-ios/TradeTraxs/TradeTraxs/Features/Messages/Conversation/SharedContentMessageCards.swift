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
        .frame(maxWidth: 280, alignment: .leading)
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
    let author: Profile?
    let imagePipeline: any ImagePipeline
    var isOutgoing: Bool
    var includesBackground: Bool = true
    var headerTitle: String = "Shared a post"

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            sharedHeader

            if let post {
                if let media = post.media.first(where: { !$0.id.isEmpty }) {
                    TradeImageView(
                        reference: media,
                        imagePipeline: imagePipeline,
                        purpose: .postImage,
                        contentMode: .fill,
                        side: 160
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
                }

                if let author {
                    HStack(spacing: ExperienceSpacing.xs) {
                        ExperienceAvatar(
                            initials: ProfileDisplay.initials(
                                displayName: author.displayName,
                                username: author.username
                            ),
                            size: 24
                        )
                        Text(author.displayName)
                            .experienceStyle(.caption, color: secondaryTextColor)
                            .lineLimit(1)
                    }
                }

                let caption = post.body.trimmingCharacters(in: .whitespacesAndNewlines)
                if !caption.isEmpty {
                    Text(truncated(caption))
                        .experienceStyle(.body, color: secondaryTextColor)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
            } else {
                Text("Loading post…")
                    .experienceStyle(.subheadline, color: secondaryTextColor)
            }
        }
        .padding(.horizontal, includesBackground ? ExperienceSpacing.sm + 2 : 0)
        .padding(.vertical, includesBackground ? ExperienceSpacing.sm : 0)
        .frame(maxWidth: 280, alignment: .leading)
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
}

struct SharedReelMessageCard: View {
    let reel: Reel?
    let author: Profile?
    let imagePipeline: any ImagePipeline
    var isOutgoing: Bool
    var includesBackground: Bool = true

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
                    TradeImageView(
                        reference: reel.thumbnail ?? reel.video,
                        imagePipeline: imagePipeline,
                        purpose: .reelThumbnail,
                        contentMode: .fill,
                        side: 160
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))

                    Image(systemName: "play.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                }

                if let author {
                    Text(author.displayName)
                        .experienceStyle(.caption, color: secondaryTextColor)
                        .lineLimit(1)
                }

                if let caption = reel.caption?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !caption.isEmpty
                {
                    Text(caption)
                        .experienceStyle(.body, color: secondaryTextColor)
                        .lineLimit(2)
                }
            } else {
                Text("Loading clip…")
                    .experienceStyle(.subheadline, color: secondaryTextColor)
            }
        }
        .padding(.horizontal, includesBackground ? ExperienceSpacing.sm + 2 : 0)
        .padding(.vertical, includesBackground ? ExperienceSpacing.sm : 0)
        .frame(maxWidth: 280, alignment: .leading)
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
}

struct SharedAchievementMessageCard: View {
    let achievement: Achievement?
    let author: Profile?
    let imagePipeline: any ImagePipeline
    var isOutgoing: Bool
    var includesBackground: Bool = true

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
                    TradeImageView(
                        reference: image,
                        imagePipeline: imagePipeline,
                        purpose: .postImage,
                        contentMode: .fill,
                        side: 140
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 140)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
                }

                Text(achievement.title)
                    .experienceStyle(.headline, color: isOutgoing ? colors.onAccent : colors.primaryText)
                    .lineLimit(2)

                if let author {
                    Text(author.displayName)
                        .experienceStyle(.caption, color: secondaryTextColor)
                        .lineLimit(1)
                }

                if let details = achievement.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !details.isEmpty
                {
                    Text(details)
                        .experienceStyle(.caption, color: secondaryTextColor)
                        .lineLimit(2)
                }
            } else {
                Text("Loading achievement…")
                    .experienceStyle(.subheadline, color: secondaryTextColor)
            }
        }
        .padding(.horizontal, includesBackground ? ExperienceSpacing.sm + 2 : 0)
        .padding(.vertical, includesBackground ? ExperienceSpacing.sm : 0)
        .frame(maxWidth: 280, alignment: .leading)
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
}
