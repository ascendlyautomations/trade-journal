import SwiftUI

/// Instagram-style Stories strip — circular avatars with unread rings.
struct FeedStoriesRow: View {
    let stories: [Story]
    let detailCache: DetailPresentationCache
    let imagePipeline: any ImagePipeline
    let onOpen: (Story) -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: ExperienceSpacing.md) {
                ForEach(stories) { story in
                    storyBubble(story)
                }
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.vertical, ExperienceSpacing.sm)
        }
        .accessibilityIdentifier("feed.stories")
    }

    private func storyBubble(_ story: Story) -> some View {
        let profile = detailCache.profile(id: story.authorProfileID)
            ?? FollowListFixtures.profile(id: story.authorProfileID)
        let trimmedUsername = profile?.username.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let username = trimmedUsername.isEmpty
            ? (profile?.displayName ?? "trader")
            : trimmedUsername

        return Button {
            onOpen(story)
        } label: {
            VStack(spacing: ExperienceSpacing.xs) {
                ZStack {
                    ring(for: story)
                        .frame(width: 68, height: 68)

                    if let profile {
                        FollowListAvatarView(
                            profile: profile,
                            imagePipeline: imagePipeline,
                            size: 58
                        )
                    } else {
                        ExperienceAvatar(initials: String(username.prefix(2)).uppercased(), size: 58)
                    }
                }

                Text(username)
                    .experienceStyle(.caption, color: colors.primaryText)
                    .lineLimit(1)
                    .frame(width: 72)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("feed.story.\(story.id.rawValue)")
        .accessibilityLabel("Story from \(username)")
    }

    @ViewBuilder
    private func ring(for story: Story) -> some View {
        if story.viewerHasSeen {
            Circle().stroke(colors.border, lineWidth: 1)
        } else {
            Circle().stroke(
                LinearGradient(
                    colors: [
                        Color(red: 0.98, green: 0.35, blue: 0.45),
                        Color(red: 0.96, green: 0.62, blue: 0.18),
                    ],
                    startPoint: .bottomLeading,
                    endPoint: .topTrailing
                ),
                lineWidth: 2.5
            )
        }
    }
}
