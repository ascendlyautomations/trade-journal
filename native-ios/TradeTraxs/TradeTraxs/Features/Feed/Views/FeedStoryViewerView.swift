import SwiftUI

/// Lightweight story viewer — aspect-fill media, owner delete, cached Story / Profile.
struct FeedStoryViewerView: View {
    @State private var viewModel: FeedStoryViewerViewModel
    private let data: DataEnvironment
    private let imagePipeline: any ImagePipeline
    private let onClose: () -> Void

    @State private var showsDeleteConfirm = false
    @State private var showsShareSheet = false

    @Environment(\.appEnvironment) private var appEnvironment

    init(
        storyID: StoryID,
        data: DataEnvironment,
        onClose: @escaping () -> Void
    ) {
        self.onClose = onClose
        self.data = data
        _viewModel = State(
            initialValue: FeedStoryViewerViewModel(
                storyID: storyID,
                feed: data.feed,
                session: data.session,
                cache: data.detailCache,
                onDismiss: onClose
            )
        )
        self.imagePipeline = data.imagePipeline
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch viewModel.phase {
            case .loading:
                ProgressView()
                    .tint(.white)
            case .unavailable, .failed:
                ExperienceEmptyState(
                    icon: .photo,
                    title: "Story unavailable",
                    message: "This story has expired or was deleted."
                )
                .foregroundStyle(.white)
            case .loaded:
                if let story = viewModel.story {
                    storyContent(story)
                }
            }
        }
        .experienceSwipeToDismiss(onDismiss: onClose)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", action: onClose)
                    .foregroundStyle(.white)
            }
            if viewModel.phase == .loaded {
                ToolbarItem(placement: .topBarTrailing) {
                    DetailOverflowMenu(
                        isOwner: viewModel.isOwner,
                        shareTitle: "Share Story",
                        onShare: viewModel.story == nil ? nil : { showsShareSheet = true },
                        onCopyLink: {
                            DetailOverflowActions.copyLink(.story(viewModel.storyID))
                        },
                        onReport: storyReportAction,
                        deleteTitle: "Delete Story",
                        onDelete: viewModel.isOwner ? { showsDeleteConfirm = true } : nil,
                        accessibilityIdentifier: "feed.story.overflow"
                    )
                    .foregroundStyle(.white)
                }
            }
        }
        .confirmationDialog(
            "Delete Story?",
            isPresented: $showsDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Story", role: .destructive) {
                Task { _ = await viewModel.deleteStory() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This story will be permanently removed.")
        }
        .alert(
            "Couldn't delete story",
            isPresented: Binding(
                get: { viewModel.deleteErrorMessage != nil },
                set: { if !$0 { viewModel.clearDeleteError() } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.deleteErrorMessage ?? "")
        }
        .interactiveDismissDisabled(viewModel.isDeleting)
        .sheet(isPresented: $showsShareSheet) {
            if let story = viewModel.story {
                StoryShareSheet(
                    story: story,
                    ownerUsername: viewModel.author?.username,
                    data: data,
                    onClose: { showsShareSheet = false }
                )
            }
        }
        .task { await viewModel.loadIfNeeded() }
        .accessibilityIdentifier("feed.story.viewer")
    }

    private var storyReportAction: (() -> Void)? {
        guard !viewModel.isOwner,
              let ownerID = viewModel.author?.id ?? viewModel.story?.authorProfileID
        else { return nil }
        return {
            ExperienceHaptics.play(.selection)
            appEnvironment.contentReportPresenter.present(
                ContentReportRequest(
                    target: .story(viewModel.storyID, ownerID: ownerID),
                    subjectTitle: "this story",
                    blockUserOffer: ownerID
                )
            )
        }
    }

    @ViewBuilder
    private func storyContent(_ story: Story) -> some View {
        VStack(spacing: 0) {
            header(for: story)
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.top, ExperienceSpacing.sm)

            StoryAspectFillMediaView(
                reference: story.media,
                imagePipeline: imagePipeline
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(for story: Story) -> some View {
        let profile = viewModel.author
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
