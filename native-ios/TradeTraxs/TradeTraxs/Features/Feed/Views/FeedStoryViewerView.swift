import SwiftUI

/// Instagram-style story viewer — multi-slide carousel, tap navigation, private DM replies.
struct FeedStoryViewerView: View {
    @State private var viewModel: FeedStoryViewerViewModel
    private let data: DataEnvironment
    private let imagePipeline: any ImagePipeline
    private let onClose: () -> Void

    @State private var showsDeleteConfirm = false
    @State private var showsShareSheet = false
    @State private var replyText = ""
    @State private var isReplyFocused = false

    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.scenePhase) private var scenePhase

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
                messages: data.messages,
                session: data.session,
                cache: data.detailCache,
                objectStorage: data.objectStorage,
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
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", action: closeViewer)
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
        .alert(
            "Couldn't send message",
            isPresented: Binding(
                get: { viewModel.replyErrorMessage != nil },
                set: { if !$0 { viewModel.clearReplyError() } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.replyErrorMessage ?? "")
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
        .onDisappear { viewModel.tearDown() }
        .onChange(of: isReplyFocused) { _, focused in
            viewModel.setReplyComposerActive(focused)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                viewModel.setBackgroundPaused(false)
            case .background, .inactive:
                viewModel.setBackgroundPaused(true)
            @unknown default:
                break
            }
        }
        .accessibilityIdentifier("feed.story.viewer")
    }

    private func closeViewer() {
        viewModel.dismissViewer()
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
                .padding(.bottom, ExperienceSpacing.sm)

            ZStack {
                StoryPlaybackMediaView(
                    reference: story.media,
                    imagePipeline: imagePipeline,
                    player: viewModel.playback.player,
                    isVideo: viewModel.isVideoStory
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(story.id)
                .storyHoldToPause(isEnabled: !isReplyFocused) { holding in
                    viewModel.setHoldPaused(holding)
                }

                storyTapNavigationOverlay
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if viewModel.showReplyComposer {
                StoryReplyInputView(
                    text: $replyText,
                    isFocused: $isReplyFocused,
                    isSending: viewModel.isSendingReply,
                    onSend: {
                        Task {
                            let draft = replyText
                            let sent = await viewModel.sendStoryReply(text: draft)
                            if sent {
                                replyText = ""
                                isReplyFocused = false
                            }
                        }
                    }
                )
            }
        }
        .safeAreaPadding(.bottom)
        .simultaneousGesture(storyDragGesture)
    }

    private var storyDragGesture: some Gesture {
        StoryViewerDragGestureSupport.dragGesture(
            isReplyFocused: isReplyFocused,
            canOpenReplyComposer: viewModel.showReplyComposer,
            onSwipeDown: closeViewer,
            onSwipeUp: { isReplyFocused = true },
            onSwipeLeft: { viewModel.goNextAuthor() },
            onSwipeRight: { viewModel.goPreviousAuthor() }
        )
    }

    private var storyTapNavigationOverlay: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: proxy.size.width * 0.38)
                    .onTapGesture { viewModel.goPreviousSlide() }
                    .accessibilityLabel("Previous story")

                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: proxy.size.width * 0.62)
                    .onTapGesture { viewModel.goNextSlide() }
                    .accessibilityLabel("Next story")
            }
        }
        .allowsHitTesting(!isReplyFocused)
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
