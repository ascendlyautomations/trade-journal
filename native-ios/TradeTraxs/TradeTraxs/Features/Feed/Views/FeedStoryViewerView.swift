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
            case .failed:
                ProgressView()
                    .tint(.white)
            case .loaded:
                if let story = viewModel.story {
                    storyContent(story)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .experienceSwipeToDismiss(
            isEnabled: canSwipeToDismiss,
            distanceThreshold: 72,
            velocityThreshold: 650,
            onDismiss: closeViewer
        )
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
        .task {
            await viewModel.loadIfNeeded()
            await viewModel.watchStoryLifecycle()
        }
        .onDisappear { viewModel.tearDown() }
        .onChange(of: ContentMutationStore.shared.revision) { _, _ in
            viewModel.absorbLatestContentMutation()
        }
        .onChange(of: viewModel.phase) { _, phase in
            if case .failed = phase {
                closeViewer()
            }
        }
        .onChange(of: isReplyFocused) { _, focused in
            viewModel.setReplyComposerActive(focused)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                viewModel.setBackgroundPaused(false)
                Task { await viewModel.revalidateVisibleStory() }
            case .background, .inactive:
                viewModel.setBackgroundPaused(true)
            @unknown default:
                break
            }
        }
        .accessibilityIdentifier("feed.story.viewer")
    }

    private var canSwipeToDismiss: Bool {
        !viewModel.isDeleting && !isReplyFocused
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
        ZStack {
            StoryPlaybackMediaView(
                reference: story.media,
                imagePipeline: imagePipeline,
                objectStorage: data.objectStorage,
                player: viewModel.playback.player,
                isVideo: viewModel.isVideoStory
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(story.id)
            .storyHoldToPause(isEnabled: !isReplyFocused) { holding in
                viewModel.setHoldPaused(holding)
            }

            if viewModel.isVideoStory, !viewModel.videoTextOverlays.isEmpty {
                StoryVideoTextPlaybackOverlay(
                    overlays: viewModel.videoTextOverlays,
                    videoPixelSize: viewModel.videoPixelSize
                )
                .allowsHitTesting(false)
                .accessibilityIdentifier("storyViewer.textOverlays")
            }

            storyTapNavigationOverlay

            VStack(spacing: 0) {
                storyTopChrome(for: story)
                Spacer(minLength: 0)
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
            .safeAreaPadding(.top, StoryViewerChromeMetrics.topBreathingRoom)
            .safeAreaPadding(.bottom)
        }
        .simultaneousGesture(storyHorizontalDragGesture)
    }

    @ViewBuilder
    private var storyOverflowMenu: some View {
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
        .symbolRenderingMode(.monochrome)
    }

    private var storyHorizontalDragGesture: some Gesture {
        StoryViewerDragGestureSupport.dragGesture(
            isReplyFocused: isReplyFocused,
            canOpenReplyComposer: viewModel.showReplyComposer,
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
                    .frame(width: proxy.size.width * 0.35)
                    .onTapGesture { viewModel.goPreviousSlide() }
                    .accessibilityLabel("Previous story")

                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: proxy.size.width * 0.65)
                    .onTapGesture { viewModel.goNextSlide() }
                    .accessibilityLabel("Next story")
            }
        }
        .allowsHitTesting(!isReplyFocused)
    }

    private func storyTopChrome(for story: Story) -> some View {
        let slides = viewModel.currentSlides
        let profile = viewModel.author

        return VStack(alignment: .leading, spacing: StoryViewerChromeMetrics.sectionSpacing) {
            if slides.count > 1 {
                StorySlideProgressStrip(
                    slideCount: slides.count,
                    activeIndex: min(max(viewModel.slideIndex, 0), slides.count - 1)
                )
            }

            HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
                HStack(spacing: ExperienceSpacing.sm) {
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
                            .lineLimit(1)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityElement(children: .combine)

                Spacer(minLength: ExperienceSpacing.sm)
                    .allowsHitTesting(false)

                storyOverflowMenu
            }
        }
        .padding(.horizontal, StoryViewerChromeMetrics.horizontalInset)
        .padding(.bottom, ExperienceSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
