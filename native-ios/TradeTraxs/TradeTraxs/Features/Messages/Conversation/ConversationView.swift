import SwiftUI
import UIKit

/// Production conversation thread — replaces the Messages `thread` placeholder.
struct ConversationView: View {
    @State private var viewModel: ConversationViewModel
    @State private var contentRevealed = false
    @State private var appliedScrollCommandGeneration: UInt64 = 0
    @State private var initialScrollRetryTask: Task<Void, Never>?
    @State private var settlingStabilityTask: Task<Void, Never>?
    @State private var lastScrollContentHeight: CGFloat = 0
    @State private var lastScrollSample: ScrollLayoutSample?
    @State private var userReleasedInitialPin = false
    @State private var showsConversationActions = false
    private let imagePipeline: any ImagePipeline
    private let detailCache: DetailPresentationCache
    private let navigationCoordinator: NavigationCoordinator?

    @Environment(\.themeColors) private var colors
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let bottomProximityThreshold: CGFloat = 80
    private static let userScrollReleaseThreshold: CGFloat = 120
    private static let settlingStabilityDelayNs: UInt64 = 150_000_000

    private struct ScrollLayoutSample: Equatable {
        let contentHeight: CGFloat
        let contentOffsetY: CGFloat
        let containerHeight: CGFloat
        let isNearBottom: Bool

        var distanceFromBottom: CGFloat {
            contentHeight - contentOffsetY - containerHeight
        }
    }

    init(
        conversationID: ConversationID,
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator? = nil
    ) {
        _viewModel = State(
            initialValue: ConversationViewModel(
                conversationID: conversationID,
                messages: data.messages,
                profiles: data.profiles,
                session: data.session,
                uploadService: data.uploadService,
                objectStorage: data.objectStorage,
                detailCache: data.detailCache,
                trades: data.trades,
                notifications: data.notifications,
                realtimeHub: data.realtimeHub,
                rpc: data.rpc
            )
        )
        self.imagePipeline = data.imagePipeline
        self.detailCache = data.detailCache
        self.navigationCoordinator = navigationCoordinator
    }

    /// Test / previews.
    init(viewModel: ConversationViewModel, imagePipeline: any ImagePipeline) {
        _viewModel = State(initialValue: viewModel)
        self.imagePipeline = imagePipeline
        self.detailCache = DetailPresentationCache()
        self.navigationCoordinator = nil
    }

    var body: some View {
        VStack(spacing: 0) {
            content
            if let deleteErrorMessage = viewModel.deleteErrorMessage {
                Text(deleteErrorMessage)
                    .experienceStyle(.caption, color: colors.error)
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.vertical, ExperienceSpacing.xs)
            }
            if !viewModel.isSelectionMode,
               !viewModel.isMessagingBlocked,
               viewModel.phase == .loaded || viewModel.showsEmpty || !viewModel.messages.isEmpty
            {
                ConversationComposerView(viewModel: viewModel, imagePipeline: imagePipeline)
            } else if viewModel.isMessagingBlocked {
                blockedComposerBanner
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.isSelectionMode {
                selectionActionBar
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle(viewModel.isSelectionMode ? viewModel.selectionToolbarTitle : viewModel.title)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if viewModel.isSelectionMode {
                    Button("Cancel") {
                        viewModel.cancelSelectionMode()
                    }
                    .accessibilityIdentifier("conversation.selection.cancel")
                }
            }
            ToolbarItem(placement: .principal) {
                if viewModel.isSelectionMode {
                    Text(viewModel.selectionToolbarTitle)
                        .experienceStyle(.headline, color: colors.primaryText)
                        .lineLimit(1)
                        .accessibilityIdentifier("conversation.selection.title")
                } else {
                    conversationHeaderTitle
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !viewModel.isSelectionMode, viewModel.showsDirectMessageActions {
                    Button {
                        showsConversationActions = true
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(colors.primaryText)
                    }
                    .accessibilityLabel("Conversation actions")
                    .accessibilityIdentifier("conversation.actions.menu")
                }
            }
        }
        .confirmationDialog("Conversation", isPresented: $showsConversationActions, titleVisibility: .visible) {
            Button("Select Messages") {
                viewModel.enterSelectionMode()
            }
            Button(viewModel.isMuted ? "Unmute Conversation" : "Mute Conversation") {
                viewModel.toggleMute()
            }
            if let peerProfileID = viewModel.peerProfileID {
                Button("Report User", role: .destructive) {
                    ExperienceHaptics.play(.selection)
                    ContentReportSupport.presentUser(
                        profileID: peerProfileID,
                        displayName: viewModel.peerProfile?.displayName,
                        presenter: appEnvironment.contentReportPresenter
                    )
                }
            }
            if viewModel.blockedByMe {
                Button("Unblock User") {
                    viewModel.requestBlockToggle()
                }
            } else {
                Button("Block User", role: .destructive) {
                    viewModel.requestBlockToggle()
                }
            }
            Button("Delete Conversation", role: .destructive) {
                viewModel.requestDeleteConversation()
            }
            if viewModel.peerProfileID != nil {
                Button("View Profile") {
                    if let profileID = viewModel.peerProfileID {
                        openPeerProfile(profileID)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(viewModel.blockConfirmationTitle, isPresented: $viewModel.showsBlockConfirmation) {
            Button(viewModel.blockedByMe ? "Unblock" : "Block", role: viewModel.blockedByMe ? nil : .destructive) {
                Task { await viewModel.confirmBlockToggle() }
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingBlockAction = nil
            }
        } message: {
            Text(viewModel.blockConfirmationMessage)
        }
        .alert("Delete Conversation?", isPresented: $viewModel.showsDeleteConversationConfirmation) {
            Button("Delete", role: .destructive) {
                Task { await viewModel.confirmDeleteConversation() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove this conversation from your messages.")
        }
        .alert(viewModel.batchDeleteConfirmationTitle, isPresented: $viewModel.showsBatchDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task { await viewModel.confirmDeleteSelectedMessages() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Couldn't delete conversation",
            isPresented: Binding(
                get: { viewModel.deleteConversationErrorMessage != nil },
                set: { presented in
                    if !presented { viewModel.deleteConversationErrorMessage = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                viewModel.deleteConversationErrorMessage = nil
            }
        } message: {
            Text(viewModel.deleteConversationErrorMessage ?? "")
        }
        .onChange(of: viewModel.shouldDismissAfterConversationDelete) { _, shouldDismiss in
            guard shouldDismiss else { return }
            navigationCoordinator?.pop()
        }
        .experienceDetailEntry(revealed: contentRevealed, reduceMotion: reduceMotion)
        .onAppear {
            guard !contentRevealed else { return }
            ExperienceMotion.withAnimation(
                ExperienceMotion.navigation,
                reduceMotion: reduceMotion
            ) {
                contentRevealed = true
            }
        }
        .task {
            resetInitialScrollSessionState()
            viewModel.resetInitialScrollPhase()
            viewModel.loadIfNeeded()
            #if DEBUG
            await applyConversationScreenshotHooksIfNeeded()
            #endif
        }
        .onDisappear {
            resetInitialScrollSessionState()
            viewModel.stopRealtime()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            guard viewModel.isInitialScrollConfirmed else { return }
            guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
                return
            }
            let screenHeight = UIScreen.main.bounds.height
            let isVisible = frame.minY < screenHeight
            viewModel.scrollCoordinator.reportKeyboardVisible(
                isVisible,
                conversationID: viewModel.conversationID
            )
        }
    }

    #if DEBUG
    private func applyConversationScreenshotHooksIfNeeded() async {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-uitesting-messages-thread-send") else { return }
        // Wait for fixture timeline to settle, then send one optimistic message.
        for _ in 0..<20 {
            if viewModel.phase == .loaded { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard viewModel.phase == .loaded else { return }
        viewModel.draft = "Locked in — R:R looks clean."
        await viewModel.sendText()
    }
    #endif

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle, .loading:
            if viewModel.messages.isEmpty {
                ExperienceLoadingSpinner(label: "Loading conversation")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                messageList
            }
        case .failed(let message):
            if viewModel.messages.isEmpty {
                ExperienceErrorState(
                    title: "Couldn't load conversation",
                    message: message,
                    onRetry: { viewModel.retryLoad() }
                )
            } else {
                // Keep cached thread visible while offline / after a soft refresh failure.
                messageList
            }
        case .loaded where viewModel.showsEmpty:
            ExperienceEmptyState(
                icon: .messages,
                title: "No messages yet",
                message: "Say hello to start the conversation."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            messageList
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: ExperienceSpacing.xs) {
                    if viewModel.hasMoreOlder, viewModel.isInitialScrollConfirmed {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, ExperienceSpacing.sm)
                            .onAppear {
                                Task { await viewModel.loadOlderIfNeeded() }
                            }
                    }

                    ForEach(viewModel.timeline) { item in
                        switch item {
                        case .daySeparator(_, let title):
                            ConversationDaySeparatorView(title: title)
                        case .message(let bubble):
                            ConversationBubbleView(
                                item: bubble,
                                peerProfile: viewModel.peerProfile,
                                imagePipeline: imagePipeline,
                                viewerProfileID: viewModel.viewerID,
                                sharedTrade: viewModel.sharedTrade(for: bubble.message),
                                canDelete: viewModel.canDeleteMessage(bubble),
                                onRetry: {
                                    Task { await viewModel.retry(bubble) }
                                },
                                onDelete: {
                                    Task { await viewModel.deleteMessage(bubble) }
                                },
                                onSharedTradeTap: { tradeID in
                                    navigationCoordinator?.pushMessages(.sharedTrade(tradeID))
                                },
                                onSharedStoryTap: { payload in
                                    StoryShareNavigation.open(
                                        payload: payload,
                                        cache: detailCache,
                                        coordinator: navigationCoordinator
                                    )
                                },
                                isSelectionMode: viewModel.isSelectionMode,
                                isSelected: viewModel.isMessageSelected(bubble.id),
                                onToggleSelection: {
                                    viewModel.toggleMessageSelection(bubble.id)
                                },
                                onReport: incomingMessageReportAction(for: bubble)
                            )
                            .id(bubble.id.rawValue)
                            .onAppear {
                                guard viewModel.isInitialScrollPinningBottom else { return }
                                guard bubble.id == viewModel.newestMessageID else { return }
                                scrollToLatest(
                                    proxy: proxy,
                                    animated: false,
                                    reason: "newest-bubble-onAppear"
                                )
                            }
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(ConversationScrollAnchorID.bottom)
                        .onAppear {
                            guard viewModel.isInitialScrollPinningBottom else { return }
                            scrollToLatest(
                                proxy: proxy,
                                animated: false,
                                reason: "bottom-anchor-onAppear"
                            )
                        }
                }
                .padding(.vertical, ExperienceSpacing.sm)
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(initialScrollReleaseGesture)
            .onScrollGeometryChange(for: ScrollLayoutSample.self) { geometry in
                let distanceFromBottom = geometry.contentSize.height
                    - geometry.contentOffset.y
                    - geometry.containerSize.height
                return ScrollLayoutSample(
                    contentHeight: geometry.contentSize.height,
                    contentOffsetY: geometry.contentOffset.y,
                    containerHeight: geometry.containerSize.height,
                    isNearBottom: distanceFromBottom <= Self.bottomProximityThreshold
                )
            } action: { _, sample in
                lastScrollSample = sample
                handleInitialScrollGeometry(sample, proxy: proxy)
                guard viewModel.isInitialScrollConfirmed else { return }
                viewModel.scrollCoordinator.reportNearBottom(
                    sample.isNearBottom,
                    conversationID: viewModel.conversationID
                )
            }
            .onChange(of: viewModel.scrollCoordinator.scrollCommandGeneration) { _, _ in
                applyCoordinatorScrollCommand(proxy: proxy)
            }
            .onChange(of: viewModel.phase) { _, phase in
                guard phase == .loaded else { return }
                if viewModel.showsEmpty {
                    viewModel.confirmInitialScrollPositionForEmptyThread()
                } else {
                    startInitialScrollPositioning(proxy: proxy, reason: "phase-loaded")
                }
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                guard viewModel.isInitialScrollPinningBottom else { return }
                guard !viewModel.messages.isEmpty else { return }
                startInitialScrollPositioning(proxy: proxy, reason: "messages-count")
            }
            .onChange(of: viewModel.sharedTrades.count) { _, _ in
                guard viewModel.initialScrollPhase == .settling else { return }
                guard let proxySample = lastScrollSample else { return }
                maintainInitialBottomPin(
                    sample: proxySample,
                    proxy: proxy,
                    reason: "shared-trades-hydrated"
                )
                scheduleSettlingStabilityCheck(proxy: proxy)
            }
            .overlay(alignment: .bottom) {
                if viewModel.scrollCoordinator.showsNewMessagesIndicator {
                    newMessagesIndicator(proxy: proxy)
                }
            }
            .accessibilityIdentifier("conversation.messageList")
            .onAppear {
                if viewModel.showsEmpty, viewModel.phase == .loaded {
                    viewModel.confirmInitialScrollPositionForEmptyThread()
                } else if !viewModel.messages.isEmpty {
                    startInitialScrollPositioning(proxy: proxy, reason: "messageList-onAppear")
                }
            }
            .onDisappear {
                resetInitialScrollSessionState()
            }
        }
    }

    private var initialScrollReleaseGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard viewModel.isInitialScrollPinningBottom else { return }
                guard value.translation.height > 0 else { return }
                releaseInitialBottomPinToUser(reason: "user-drag-up")
            }
    }

    private func resetInitialScrollSessionState() {
        initialScrollRetryTask?.cancel()
        settlingStabilityTask?.cancel()
        lastScrollContentHeight = 0
        lastScrollSample = nil
        userReleasedInitialPin = false
    }

    private func releaseInitialBottomPinToUser(reason: String) {
        guard !userReleasedInitialPin else { return }
        guard viewModel.isInitialScrollPinningBottom else { return }
        userReleasedInitialPin = true
        settlingStabilityTask?.cancel()
        initialScrollRetryTask?.cancel()
#if DEBUG
        ConversationScrollDiagnostics.logInitialScrollPhase(
            "release-\(reason)",
            conversationID: viewModel.conversationID,
            messageCount: viewModel.messages.count,
            newestMessageID: viewModel.newestMessageID,
            pendingRichLayout: viewModel.hasPendingRichContentLayout
        )
#endif
        viewModel.confirmInitialScrollPosition(userInitiatedRelease: true)
    }

    private func newMessagesIndicator(proxy: ScrollViewProxy) -> some View {
        Button {
            viewModel.scrollCoordinator.jumpToLatest(conversationID: viewModel.conversationID)
            applyCoordinatorScrollCommand(proxy: proxy)
        } label: {
            HStack(spacing: ExperienceSpacing.xs) {
                Image(systemName: "chevron.down")
                Text("New messages")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(colors.primaryText)
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.vertical, ExperienceSpacing.xs)
            .background(
                colors.navigationBackground.opacity(0.96),
                in: Capsule(style: .continuous)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(colors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.bottom, ExperienceSpacing.sm)
        .accessibilityIdentifier("conversation.newMessagesIndicator")
    }

    private var conversationHeaderTitle: some View {
        Group {
            if viewModel.showsDirectMessageActions, let profileID = viewModel.peerProfileID {
                Button {
                    openPeerProfile(profileID)
                } label: {
                    conversationHeaderTitleContent
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View \(viewModel.title)'s profile")
                .accessibilityHint("Opens profile")
            } else {
                conversationHeaderTitleContent
            }
        }
        .accessibilityIdentifier("conversation.header")
    }

    private var conversationHeaderTitleContent: some View {
        VStack(spacing: 1) {
            Text(viewModel.title)
                .experienceStyle(.headline, color: colors.primaryText)
                .lineLimit(1)
            if let subtitle = viewModel.subtitle {
                Text(subtitle)
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, ExperienceSpacing.xs)
        .padding(.vertical, 2)
    }

    private func openPeerProfile(_ profileID: ProfileID) {
        ExperienceHaptics.play(.selection)
        navigationCoordinator?.pushMessages(.profile(profileID))
    }

    private var blockedComposerBanner: some View {
        Text(viewModel.blockedByMe
            ? "You blocked this user. Unblock them to send messages."
            : "Messaging is unavailable while this user is blocked.")
            .experienceStyle(.footnote, color: colors.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.vertical, ExperienceSpacing.sm)
            .background(colors.navigationBackground.opacity(0.96))
            .accessibilityIdentifier("conversation.blockedBanner")
    }

    private var selectionActionBar: some View {
        HStack {
            Spacer()
            Button(role: .destructive) {
                viewModel.requestDeleteSelectedMessages()
            } label: {
                Text("Delete")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .disabled(viewModel.selectedDeletableMessages.isEmpty)
            .accessibilityIdentifier("conversation.selection.delete")
            Spacer()
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.vertical, ExperienceSpacing.sm)
        .background(.bar)
    }

    private func startInitialScrollPositioning(proxy: ScrollViewProxy, reason: String) {
        guard !viewModel.isInitialScrollConfirmed else { return }
        guard !viewModel.messages.isEmpty else { return }

        if viewModel.initialScrollPhase == .pending {
            viewModel.beginInitialScrollPositioning()
            scheduleInitialScrollRetries(proxy: proxy)
        }

        scrollToLatest(proxy: proxy, animated: false, reason: reason)
    }

    private func handleInitialScrollGeometry(_ sample: ScrollLayoutSample, proxy: ScrollViewProxy) {
        let contentSizeDelta = sample.contentHeight - lastScrollContentHeight
        lastScrollContentHeight = sample.contentHeight

        switch viewModel.initialScrollPhase {
        case .pending:
            break
        case .positioning:
            guard sample.isNearBottom else { return }
            viewModel.beginInitialScrollSettling()
            scrollToLatest(proxy: proxy, animated: false, reason: "enter-settling")
            scheduleSettlingStabilityCheck(proxy: proxy)
        case .settling:
            if userReleasedInitialPin {
                return
            }
            if contentSizeDelta <= 1,
               sample.distanceFromBottom > Self.userScrollReleaseThreshold
            {
                releaseInitialBottomPinToUser(reason: "scroll-offset-away-from-bottom")
                return
            }
            maintainInitialBottomPin(sample: sample, proxy: proxy, reason: "layout-geometry-change")
            scheduleSettlingStabilityCheck(proxy: proxy)
        case .confirmed:
            break
        }
    }

    private func maintainInitialBottomPin(
        sample: ScrollLayoutSample,
        proxy: ScrollViewProxy,
        reason: String
    ) {
        guard viewModel.initialScrollPhase == .settling else { return }
        guard !userReleasedInitialPin else { return }
        if sample.contentHeight > 0,
           (!sample.isNearBottom || sample.distanceFromBottom > Self.bottomProximityThreshold / 2)
        {
            scrollToLatest(proxy: proxy, animated: false, reason: reason)
        }
    }

    private func scheduleSettlingStabilityCheck(proxy: ScrollViewProxy) {
        guard viewModel.initialScrollPhase == .settling else { return }
        guard !userReleasedInitialPin else { return }

        settlingStabilityTask?.cancel()
        let baselineHeight = lastScrollContentHeight
        settlingStabilityTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.settlingStabilityDelayNs)
            guard !Task.isCancelled else { return }
            guard viewModel.initialScrollPhase == .settling else { return }
            guard !userReleasedInitialPin else { return }
            guard lastScrollContentHeight == baselineHeight else { return }
            guard !viewModel.hasPendingRichContentLayout else { return }
            guard lastScrollSample?.isNearBottom == true else { return }

            scrollToLatest(proxy: proxy, animated: false, reason: "settling-stable")
            viewModel.confirmInitialScrollPosition()
        }
    }

    private func scheduleInitialScrollRetries(proxy: ScrollViewProxy) {
        initialScrollRetryTask?.cancel()
        initialScrollRetryTask = Task { @MainActor in
            for attempt in 1...8 {
                guard !Task.isCancelled else { return }
                guard viewModel.isInitialScrollPinningBottom else { return }
                scrollToLatest(proxy: proxy, animated: false, reason: "retry-\(attempt)")
                try? await Task.sleep(nanoseconds: 32_000_000)
            }
        }
    }

    private func scrollToLatest(proxy: ScrollViewProxy, animated: Bool, reason: String) {
        let newest = viewModel.newestMessageID
        let target = newest?.rawValue ?? ConversationScrollAnchorID.bottom
        let targetExists = viewModel.timeline.contains(where: { item in
            if case .message(let bubble) = item {
                return bubble.id.rawValue == target
            }
            return target == ConversationScrollAnchorID.bottom
        })

        #if DEBUG
        ConversationScrollDiagnostics.logScrollAttempt(
            reason: reason,
            conversationID: viewModel.conversationID,
            newestMessageID: newest,
            firstMessageID: viewModel.messages.first?.id,
            lastMessageID: viewModel.messages.last?.id,
            targetID: target,
            targetExistsInTimeline: targetExists,
            initialScrollPhase: String(describing: viewModel.initialScrollPhase),
            phase: String(describing: viewModel.phase),
            messageCount: viewModel.messages.count,
            hasMoreOlder: viewModel.hasMoreOlder
        )
        #endif

        let action = {
            proxy.scrollTo(target, anchor: .bottom)
        }
        DispatchQueue.main.async {
            if animated {
                ExperienceMotion.withAnimation(
                    MotionCurve.easeOut.animation(duration: .fast),
                    reduceMotion: reduceMotion,
                    action
                )
            } else {
                action()
            }
        }
    }

    private func applyCoordinatorScrollCommand(proxy: ScrollViewProxy) {
        guard viewModel.isInitialScrollConfirmed else { return }
        let coordinator = viewModel.scrollCoordinator
        guard coordinator.scrollCommandGeneration != appliedScrollCommandGeneration else { return }
        guard let target = coordinator.desiredScrollPositionID else { return }
        appliedScrollCommandGeneration = coordinator.scrollCommandGeneration

        #if DEBUG
        ConversationScrollDiagnostics.logCoordinatorCommand(
            reason: "coordinator-command",
            targetID: target,
            animated: coordinator.desiredScrollAnimated,
            mode: String(describing: coordinator.mode),
            initialScrollCompleted: viewModel.isInitialScrollConfirmed
        )
        #endif

        let apply = {
            proxy.scrollTo(target, anchor: .bottom)
        }
        DispatchQueue.main.async {
            if coordinator.desiredScrollAnimated {
                ExperienceMotion.withAnimation(
                    MotionCurve.easeOut.animation(duration: .fast),
                    reduceMotion: reduceMotion,
                    apply
                )
            } else {
                apply()
            }
        }
    }

    private func incomingMessageReportAction(for bubble: ConversationBubbleItem) -> (() -> Void)? {
        guard !bubble.isOutgoing else { return nil }
        return {
            ExperienceHaptics.play(.selection)
            ContentReportSupport.presentDirectMessage(
                message: bubble.message,
                presenter: appEnvironment.contentReportPresenter
            )
        }
    }
}
