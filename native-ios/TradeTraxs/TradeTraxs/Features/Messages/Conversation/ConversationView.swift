import SwiftUI

/// Production conversation thread — replaces the Messages `thread` placeholder.
struct ConversationView: View {
    @State private var viewModel: ConversationViewModel
    private let imagePipeline: any ImagePipeline
    private let navigationCoordinator: NavigationCoordinator?

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                realtimeHub: data.realtimeHub
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
            if viewModel.phase == .loaded || viewModel.showsEmpty {
                ConversationComposerView(viewModel: viewModel)
            }
        }
        .experienceScreenBackground()
        .navigationTitle(viewModel.title)
        .navigationBarTitleDisplayMode(.inline)
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
        .task {
            viewModel.loadIfNeeded()
            #if DEBUG
            await applyConversationScreenshotHooksIfNeeded()
            #endif
        }
        .onDisappear {
            viewModel.stopRealtime()
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
            ExperienceLoadingSpinner(label: "Loading conversation")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ExperienceErrorState(
                title: "Couldn't load conversation",
                message: message,
                onRetry: { viewModel.retryLoad() }
            )
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
                    if viewModel.hasMoreOlder {
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
                        .id(ConversationScrollAnchor.bottom)
                }
                .padding(.vertical, ExperienceSpacing.sm)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy: proxy, animated: !reduceMotion)
            }
            .onChange(of: viewModel.phase) { _, phase in
                if phase == .loaded {
                    scrollToBottom(proxy: proxy, animated: false)
                }
            }
            .accessibilityIdentifier("conversation.messageList")
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        let action = {
            proxy.scrollTo(ConversationScrollAnchor.bottom, anchor: .bottom)
        }
        if animated {
            withAnimation(.easeOut(duration: 0.22), action)
        } else {
            action()
        }
    }
}

private enum ConversationScrollAnchor {
    static let bottom = "conversation-scroll-bottom"
}
