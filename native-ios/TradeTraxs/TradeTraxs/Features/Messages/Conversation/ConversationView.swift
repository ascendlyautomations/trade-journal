import SwiftUI
import UIKit

/// Production conversation thread — replaces the Messages `thread` placeholder.
struct ConversationView: View {
    @State private var viewModel: ConversationViewModel
    @State private var contentRevealed = false
    @State private var scrollPositionID: String?
    @State private var bottomAnchorLaidOut = false
    @State private var messageListLaidOut = false
    @State private var appliedScrollCommandGeneration: UInt64 = 0
    private let imagePipeline: any ImagePipeline
    private let navigationCoordinator: NavigationCoordinator?

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let bottomProximityThreshold: CGFloat = 80

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
        self.navigationCoordinator = navigationCoordinator
    }

    /// Test / previews.
    init(viewModel: ConversationViewModel, imagePipeline: any ImagePipeline) {
        _viewModel = State(initialValue: viewModel)
        self.imagePipeline = imagePipeline
        self.navigationCoordinator = nil
    }

    var body: some View {
        VStack(spacing: 0) {
            content
            if viewModel.phase == .loaded || viewModel.showsEmpty || !viewModel.messages.isEmpty {
                ConversationComposerView(viewModel: viewModel)
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle(viewModel.title)
        .toolbar {
            ToolbarItem(placement: .principal) {
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
                .accessibilityIdentifier("conversation.header")
            }
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
            viewModel.loadIfNeeded()
            #if DEBUG
            await applyConversationScreenshotHooksIfNeeded()
            #endif
        }
        .onDisappear {
            viewModel.stopRealtime()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
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
        ScrollView {
            LazyVStack(spacing: ExperienceSpacing.xs) {
                if viewModel.hasMoreOlder {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, ExperienceSpacing.sm)
                        .onAppear {
                            if let anchor = viewModel.messages.first?.id {
                                viewModel.beginPagination(anchorMessageID: anchor)
                            }
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
                            sharedTrade: viewModel.sharedTrade(for: bubble.message),
                            onRetry: {
                                Task { await viewModel.retry(bubble) }
                            }
                        )
                        .id(bubble.id.rawValue)
                    }
                }

                Color.clear
                    .frame(height: 1)
                    .id(ConversationScrollAnchorID.bottom)
                    .onAppear {
                        bottomAnchorLaidOut = true
                        reportLayoutReadyIfNeeded()
                    }
            }
            .padding(.vertical, ExperienceSpacing.sm)
        }
        .scrollPosition(id: $scrollPositionID, anchor: .bottom)
        .scrollDismissesKeyboard(.interactively)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            let distanceFromBottom = geometry.contentSize.height
                - geometry.contentOffset.y
                - geometry.containerSize.height
            return distanceFromBottom <= Self.bottomProximityThreshold
        } action: { _, isNearBottom in
            viewModel.scrollCoordinator.reportNearBottom(
                isNearBottom,
                conversationID: viewModel.conversationID
            )
        }
        .onChange(of: viewModel.scrollCoordinator.scrollCommandGeneration) { _, _ in
            applyScrollCommand()
        }
        .onChange(of: viewModel.messages.count) { _, _ in
            reportLayoutReadyIfNeeded()
        }
        .overlay(alignment: .bottom) {
            if viewModel.scrollCoordinator.showsNewMessagesIndicator {
                newMessagesIndicator
            }
        }
        .accessibilityIdentifier("conversation.messageList")
        .onAppear {
            messageListLaidOut = true
            reportLayoutReadyIfNeeded()
            applyScrollCommand()
        }
        .onDisappear {
            messageListLaidOut = false
            bottomAnchorLaidOut = false
        }
    }

    private var newMessagesIndicator: some View {
        Button {
            viewModel.scrollCoordinator.jumpToLatest(conversationID: viewModel.conversationID)
            applyScrollCommand()
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

    private func reportLayoutReadyIfNeeded() {
        guard messageListLaidOut else { return }
        if viewModel.messages.isEmpty {
            viewModel.scrollCoordinator.reportLayoutReady(
                newestMessageID: nil,
                isEmpty: true,
                conversationID: viewModel.conversationID
            )
            return
        }
        viewModel.scrollCoordinator.reportLayoutReady(
            newestMessageID: viewModel.newestMessageID,
            isEmpty: false,
            conversationID: viewModel.conversationID
        )
        applyScrollCommand()
    }

    private func applyScrollCommand() {
        let coordinator = viewModel.scrollCoordinator
        guard coordinator.scrollCommandGeneration != appliedScrollCommandGeneration else { return }
        guard let target = coordinator.desiredScrollPositionID else { return }
        appliedScrollCommandGeneration = coordinator.scrollCommandGeneration

        let apply = {
            scrollPositionID = target
        }
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
