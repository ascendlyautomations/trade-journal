import SwiftUI

/// Instagram-style Stories strip — circular avatars with unread rings.
struct FeedStoriesRow: View {
    let stories: [Story]
    let viewerID: ProfileID?
    let detailCache: DetailPresentationCache
    let imagePipeline: any ImagePipeline
    let onAddStory: () -> Void
    let onOpen: (Story) -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: ExperienceSpacing.md) {
                if let viewerID {
                    viewerStoryBubble(viewerID: viewerID)
                }
                ForEach(otherStories) { story in
                    storyBubble(story)
                }
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.vertical, ExperienceSpacing.sm)
        }
        .accessibilityIdentifier("feed.stories")
    }

    private var viewerStory: Story? {
        guard let viewerID else { return nil }
        return stories.first { $0.authorProfileID == viewerID }
    }

    private var otherStories: [Story] {
        guard let viewerID else { return stories }
        return stories.filter { $0.authorProfileID != viewerID }
    }

    private func viewerStoryBubble(viewerID: ProfileID) -> some View {
        let profile = detailCache.profile(id: viewerID)
            ?? FollowListFixtures.profile(id: viewerID)
        let trimmedUsername = profile?.username.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let username = trimmedUsername.isEmpty
            ? (profile?.displayName ?? "You")
            : trimmedUsername
        let hasActiveStory = viewerStory != nil
        let label = hasActiveStory ? username : "Add Story"

        return VStack(spacing: ExperienceSpacing.xs) {
            ZStack(alignment: .bottomTrailing) {
                Button {
                    if let story = viewerStory {
                        onOpen(story)
                    } else {
                        onAddStory()
                    }
                } label: {
                    ZStack {
                        if hasActiveStory, let story = viewerStory {
                            ring(for: story)
                                .frame(width: 68, height: 68)
                        } else {
                            Circle()
                                .strokeBorder(
                                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                                )
                                .foregroundStyle(colors.border)
                                .frame(width: 68, height: 68)
                        }

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
                }
                .buttonStyle(.plain)
                .accessibilityLabel(hasActiveStory ? "View your story" : "Add story")

                Button(action: onAddStory) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Color(red: 0.06, green: 0.72, blue: 0.45))
                        .clipShape(Circle())
                        .overlay(
                            Circle().stroke(colors.backgroundPrimary, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add story")
                .accessibilityIdentifier("feed.story.add")
            }

            Text(label)
                .experienceStyle(.caption, color: colors.primaryText)
                .lineLimit(1)
                .frame(width: 72)
        }
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
