import SwiftUI

/// Lightweight story viewer — reuses AspectFitMediaView + cached Story / Profile.
struct FeedStoryViewerView: View {
    let storyID: StoryID
    private let detailCache: DetailPresentationCache
    private let imagePipeline: any ImagePipeline
    private let onClose: () -> Void

    @Environment(\.themeColors) private var colors

    init(
        storyID: StoryID,
        data: DataEnvironment,
        onClose: @escaping () -> Void
    ) {
        self.storyID = storyID
        self.detailCache = data.detailCache
        self.imagePipeline = data.imagePipeline
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let story = detailCache.story(id: storyID) {
                VStack(spacing: 0) {
                    header(for: story)
                        .padding(.horizontal, ExperienceSpacing.md)
                        .padding(.top, ExperienceSpacing.sm)

                    Spacer(minLength: ExperienceSpacing.md)

                    AspectFitMediaView(
                        reference: story.media,
                        purpose: .storyMedia,
                        imagePipeline: imagePipeline,
                        accessibilityIdentifier: "feed.story.media",
                        emptyIcon: .photo,
                        allowsFullResolutionViewer: false
                    )

                    Spacer(minLength: ExperienceSpacing.md)
                }
            } else {
                ExperienceEmptyState(
                    icon: .photo,
                    title: "Story unavailable",
                    message: "This story may have expired."
                )
                .foregroundStyle(.white)
            }
        }
        .experienceSwipeToDismiss(onDismiss: onClose)
        .experienceNavigationTitle("Story")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", action: onClose)
                    .foregroundStyle(.white)
            }
        }
        .interactiveDismissDisabled()
        .accessibilityIdentifier("feed.story.viewer")
    }

    private func header(for story: Story) -> some View {
        let profile = detailCache.profile(id: story.authorProfileID)
        return HStack(spacing: ExperienceSpacing.sm) {
            if let profile {
                FollowListAvatarView(profile: profile, imagePipeline: imagePipeline, size: 32)
            } else {
                ExperienceAvatar(initials: "?", size: 32)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(profile?.displayName ?? "Trader")
                    .experienceStyle(.headline, color: .white)
                    .lineLimit(1)
                Text(MessagesInboxSupport.relativeTimestamp(story.createdAt))
                    .experienceStyle(.caption, color: .white.opacity(0.7))
            }
            Spacer(minLength: 0)
        }
    }
}
