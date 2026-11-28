import SwiftUI

/// Instagram-style story viewer, multi-slide carousel, tap navigation, private DM replies.
struct FeedStoryViewerView: View {
    @State private var viewModel: FeedStoryViewerViewModel
    @Bindable private var engagementStore: EngagementStore
    private let data: DataEnvironment
    private let imagePipeline: any ImagePipeline
    private let onClose: () -> Void

    @State private var showsDeleteConfirm = false
    @State private var showsShareSheet = false
    @State private var showsAnalyticsSheet = false
    @State private var pendingAnalyticsProfileID: ProfileID?
    @State private var replyText = ""
    @State private var isReplyFocused = false

    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.navigationEnvironment) private var navigationEnvironment
    @Environment(\.scenePhase) private var scenePhase

    init(
        storyID: StoryID,
        entryContext: StoryViewerEntryContext = .feedCarousel,
        data: DataEnvironment,
        onClose: @escaping () -> Void
    ) {
        self.onClose = onClose
        self.data = data
        _engagementStore = Bindable(wrappedValue: data.engagementStore)
        _viewModel = State(
            initialValue: FeedStoryViewerViewModel(
                storyID: storyID,
                entryContext: entryContext,
                feed: data.feed,
                messages: data.messages,
                session: data.session,
                cache: data.detailCache,
                objectStorage: data.objectStorage,
                engagementStore: data.engagementStore,
                onDismiss: onClose
            )
        )
        self.imagePipeline = data.imagePipeline
    }

    var body: some View {
        viewerSurface
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
        .sheet(isPresented: $showsAnalyticsSheet) {
            StoryAnalyticsSheet(
                storyID: viewModel.storyID,
                feed: data.feed,
                imagePipeline: imagePipeline,
                detailCache: data.detailCache,
                onClose: { showsAnalyticsSheet = false },
                onOpenProfile: { profileID in
                    pendingAnalyticsProfileID = profileID
                    showsAnalyticsSheet = false
                }
            )
        }
        .onChange(of: showsAnalyticsSheet) { _, isPresented in
            guard !isPresented, let profileID = pendingAnalyticsProfileID else { return }
            pendingAnalyticsProfileID = nil
            openProfileFromStoryAnalytics(profileID)
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

    private var viewerSurface: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch viewModel.phase {
            case .loading:
                ExperienceIndeterminateProgress()
                    .tint(.white)
            case .unavailable:
                Text("Could not display story")
                    .experienceStyle(.body, color: .white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, ExperienceSpacing.lg)
                    .accessibilityIdentifier("feed.story.unavailable")
            case .failed:
                ExperienceIndeterminateProgress()
                    .tint(.white)
            case .loaded:
                if let story = viewModel.story {
                    storyContent(story)
                }
            }
        }
        .environment(\.experienceKeyboardDoneToolbarSuppressed, true)
        .toolbar(.hidden, for: .navigationBar)
        .experienceSuppressKeyboardInputAccessory()
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
        .modifier(FeedStoryViewerErrorAlerts(viewModel: viewModel))
    }

    private var canSwipeToDismiss: Bool {
        !viewModel.isDeleting && !isReplyFocused
    }

    private func closeViewer() {
        dismissReplyKeyboard()
        viewModel.dismissViewer()
    }

    private func dismissReplyKeyboard() {
        guard isReplyFocused else {
            ExperienceKeyboard.dismissFormKeyboard()
            return
        }
        isReplyFocused = false
        ExperienceKeyboard.dismissFormKeyboard()
    }

    private func openStoryAuthorProfile(authorID: ProfileID) {
        ExperienceHaptics.play(.selection)
        dismissReplyKeyboard()
        closeViewer()
        navigationEnvironment.coordinator.pushProfile(.otherProfile(authorID))
    }

    private func openProfileFromStoryAnalytics(_ profileID: ProfileID) {
        dismissReplyKeyboard()
        closeViewer()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            navigationEnvironment.coordinator.pushProfile(.otherProfile(profileID))
        }
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

    /// Messages docks the composer in a bottom `VStack`; media stays full-screen in the background.
    @ViewBuilder
    private func storyContent(_ story: Story) -> some View {
        GeometryReader { proxy in
            let storyCanvas = StoryComposerGeometry.aspectFitStoryCanvas(in: proxy.size)

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                if viewModel.showReplyComposer {
                    storyReplyComposer(for: story)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background {
                storyMediaLayer(story: story, storyCanvas: storyCanvas, containerSize: proxy.size)
            }
        }
        .simultaneousGesture(storyHorizontalDragGesture)
    }

    @ViewBuilder
    private func storyMediaLayer(story: Story, storyCanvas: CGRect, containerSize: CGSize) -> some View {
        ZStack {
            StoryPlaybackMediaView(
                reference: story.media,
                imagePipeline: imagePipeline,
                objectStorage: data.objectStorage,
                player: viewModel.playback.player,
                isVideo: viewModel.isVideoStory,
                onMediaLoadFailed: { viewModel.reportMediaUnavailable() }
            )
            .frame(width: storyCanvas.width, height: storyCanvas.height)
            .position(x: storyCanvas.midX, y: storyCanvas.midY)
            .clipped()
            .id(story.id)
            .storyHoldToPause(isEnabled: !isReplyFocused) { holding in
                viewModel.setHoldPaused(holding)
            }

            if viewModel.isVideoStory, !viewModel.videoTextOverlays.isEmpty {
                StoryVideoTextPlaybackOverlay(
                    overlays: viewModel.videoTextOverlays,
                    canvasSize: storyCanvas.size
                )
                .position(x: storyCanvas.midX, y: storyCanvas.midY)
                .allowsHitTesting(false)
                .accessibilityIdentifier("storyViewer.textOverlays")
            }

            storyTapNavigationOverlay

            VStack(spacing: 0) {
                storyTopChrome(for: story)
                Spacer(minLength: 0)
            }
            .safeAreaPadding(.top, StoryViewerChromeMetrics.topBreathingRoom)
        }
        .frame(width: containerSize.width, height: containerSize.height)
    }

    @ViewBuilder
    private func storyReplyComposer(for story: Story) -> some View {
        let storyTarget = InteractionTarget.story(story.id)
        let storyEngagement = engagementStore.snapshot(for: storyTarget)
        StoryReplyInputView(
            text: $replyText,
            isFocused: $isReplyFocused,
            isSending: viewModel.isSendingReply,
            isStoryLiked: storyEngagement.viewerHasLiked,
            isTogglingStoryLike: engagementStore.isLikeInFlight(for: storyTarget),
            onToggleStoryLike: {
                Task { await viewModel.toggleCurrentStoryLike() }
            },
            onSend: {
                let draft = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !draft.isEmpty, !viewModel.isSendingReply else { return }
                isReplyFocused = false
                ExperienceKeyboard.dismissFormKeyboard()
                Task {
                    let sent = await viewModel.sendStoryReply(text: draft)
                    guard sent else { return }
                    replyText = ""
                }
            }
        )
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
            onStoryAnalytics: viewModel.isOwner ? { showsAnalyticsSheet = true } : nil,
            deleteTitle: "Delete Story",
            onDelete: viewModel.isOwner ? { showsDeleteConfirm = true } : nil,
            accessibilityIdentifier: "feed.story.overflow"
        )
        .foregroundStyle(.white)
        .symbolRenderingMode(.monochrome)
        .storyViewerHeaderContrastShadow()
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
                    .onTapGesture {
                        if isReplyFocused {
                            dismissReplyKeyboard()
                        } else {
                            viewModel.goPreviousSlide()
                        }
                    }
                    .accessibilityLabel(isReplyFocused ? "Dismiss keyboard" : "Previous story")

                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: proxy.size.width * 0.65)
                    .onTapGesture {
                        if isReplyFocused {
                            dismissReplyKeyboard()
                        } else {
                            viewModel.goNextSlide()
                        }
                    }
                    .accessibilityLabel(isReplyFocused ? "Dismiss keyboard" : "Next story")
            }
        }
    }

    private func storyTopChrome(for story: Story) -> some View {
        let slides = viewModel.currentSlides
        let profile = viewModel.author
        let authorID = profile?.id ?? story.authorProfileID
        let authorLabel = profile.map { profile in
            let handle = profile.username.trimmingCharacters(in: .whitespacesAndNewlines)
            if !handle.isEmpty { return "@\(handle)" }
            return profile.displayName
        } ?? "Trader"

        return VStack(alignment: .leading, spacing: StoryViewerChromeMetrics.sectionSpacing) {
            if slides.count > 1 {
                StorySlideProgressStrip(
                    slideCount: slides.count,
                    activeIndex: min(max(viewModel.slideIndex, 0), slides.count - 1)
                )
            }

            HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
                Button {
                    openStoryAuthorProfile(authorID: authorID)
                } label: {
                    HStack(spacing: ExperienceSpacing.sm) {
                        if let profile {
                            FollowListAvatarView(
                                profile: profile,
                                imagePipeline: imagePipeline,
                                size: 32,
                                debugSurface: "storyViewer"
                            )
                            .id(authorID)
                            .storyViewerHeaderContrastShadow()
                        } else {
                            ExperienceAvatar(initials: "?", size: 32)
                                .id(authorID)
                                .storyViewerHeaderContrastShadow()
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(authorLabel)
                                .experienceStyle(.headline, color: .white)
                                .lineLimit(1)
                                .storyViewerHeaderContrastShadow()
                            Text(MessagesInboxSupport.relativeTimestamp(story.createdAt))
                                .experienceStyle(.caption, color: .white.opacity(0.88))
                                .lineLimit(1)
                                .storyViewerHeaderContrastShadow()
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .id(authorID)
                .accessibilityLabel("Open \(authorLabel) profile")
                .accessibilityIdentifier("feed.story.authorProfile")

                Spacer(minLength: ExperienceSpacing.sm)
                    .allowsHitTesting(false)

                storyOverflowMenu
            }
        }
        .padding(.horizontal, StoryViewerChromeMetrics.horizontalInset)
        .padding(.bottom, ExperienceSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .top) {
            StoryViewerHeaderScrim()
        }
    }
}

private struct FeedStoryViewerErrorAlerts: ViewModifier {
    @Bindable var viewModel: FeedStoryViewerViewModel

    func body(content: Content) -> some View {
        content
            .alert(
                "Couldn't delete story",
                isPresented: deleteErrorPresented
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.deleteErrorMessage ?? "")
            }
            .alert(
                "Couldn't send message",
                isPresented: replyErrorPresented
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.replyErrorMessage ?? "")
            }
    }

    private var deleteErrorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.deleteErrorMessage != nil },
            set: { if !$0 { viewModel.clearDeleteError() } }
        )
    }

    private var replyErrorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.replyErrorMessage != nil },
            set: { if !$0 { viewModel.clearReplyError() } }
        )
    }
}
