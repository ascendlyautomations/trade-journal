import SwiftUI

/// Trade Room workspace — compact header + channel switcher + DM-style conversation.
struct RoomConversationView: View {
    @State private var viewModel: RoomConversationViewModel
    private let imagePipeline: any ImagePipeline
    private let data: DataEnvironment?
    private let navigationCoordinator: NavigationCoordinator?
    private let navigationHost: TradeRoomNavigationHost

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        roomID: RoomID,
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator? = nil,
        navigationHost: TradeRoomNavigationHost = .messages
    ) {
        _viewModel = State(
            initialValue: RoomConversationViewModel(
                roomID: roomID,
                rooms: data.rooms,
                profiles: data.profiles,
                session: data.session,
                uploadService: data.uploadService,
                objectStorage: data.objectStorage,
                detailCache: data.detailCache,
                trades: data.trades,
                notifications: data.notifications,
                navigationCoordinator: navigationCoordinator,
                navigationHost: navigationHost,
                realtimeHub: data.realtimeHub
            )
        )
        self.imagePipeline = data.imagePipeline
        self.data = data
        self.navigationCoordinator = navigationCoordinator
        self.navigationHost = navigationHost
    }

    init(viewModel: RoomConversationViewModel, imagePipeline: any ImagePipeline) {
        _viewModel = State(initialValue: viewModel)
        self.imagePipeline = imagePipeline
        self.data = nil
        self.navigationCoordinator = nil
        self.navigationHost = .messages
    }

    var body: some View {
        VStack(spacing: 0) {
            if let room = viewModel.room, viewModel.showsRoomChrome {
                header(for: room)
                if !viewModel.channels.isEmpty {
                    RoomChannelSwitcherView(
                        channels: viewModel.channels,
                        selectedChannelID: viewModel.selectedChannelID,
                        onSelect: { viewModel.selectChannel($0) }
                    )
                }
            }
            content
            if viewModel.showsRoomChrome, viewModel.canCompose {
                MessageComposerBar(
                    draft: $viewModel.draft,
                    isSending: viewModel.isSending,
                    placeholder: composerPlaceholder,
                    onSend: {
                        Task { await viewModel.sendText() }
                    },
                    onSendImage: { image in
                        Task { await viewModel.sendImage(image) }
                    },
                    onSendTrade: {
                        viewModel.presentTradePicker()
                    }
                )
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle(viewModel.title)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(viewModel.title)
                        .experienceStyle(.headline, color: colors.primaryText)
                        .lineLimit(1)
                    if let channel = viewModel.selectedChannel {
                        Text(channel.displayTitle)
                            .experienceStyle(.caption2, color: colors.tertiaryText)
                            .lineLimit(1)
                    }
                }
                .accessibilityIdentifier("tradeRooms.conversation.title")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(
                        viewModel.isMuted ? "Unmute notifications" : "Mute notifications",
                        systemImage: viewModel.isMuted ? "bell.fill" : "bell.slash"
                    ) {
                        viewModel.toggleMute()
                    }
                } label: {
                    ExperienceIcon(icon: .more, size: .md, color: colors.primaryText)
                }
                .accessibilityIdentifier("tradeRooms.conversation.menu")
            }
        }
        .sheet(isPresented: $viewModel.showsTradePicker) {
            TradeSharePickerSheet(
                trades: viewModel.tradePickerTrades,
                isLoading: viewModel.isLoadingTradePicker,
                onSelect: { trade in
                    Task { await viewModel.sendTrade(trade) }
                },
                onClose: { viewModel.showsTradePicker = false }
            )
            .task { await viewModel.loadTradePickerIfNeeded() }
        }
        .task {
            viewModel.loadIfNeeded()
        }
        .onDisappear {
            viewModel.stopRealtime()
        }
    }

    private var composerPlaceholder: String {
        if let channel = viewModel.selectedChannel {
            return "Message \(channel.displayTitle)"
        }
        return "Message the room"
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle, .loading:
            if viewModel.messages.isEmpty {
                ExperienceLoadingSpinner(label: "Loading room")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                messageList
            }
        case .failed(let message):
            if viewModel.messages.isEmpty {
                ExperienceErrorState(
                    title: "Couldn't load room",
                    message: message,
                    onRetry: { viewModel.retryLoad() }
                )
            } else {
                messageList
            }
        case .loaded:
            if viewModel.channels.isEmpty {
                ExperienceEmptyState(
                    icon: .rooms,
                    title: "No channels yet",
                    message: "Channels for this Trade Room will appear here."
                )
            } else {
                messageList
            }
        }
    }

    private func header(for room: TradeRoom) -> some View {
        RoomConversationHeaderView(
            room: room,
            channelTitle: viewModel.selectedChannel?.displayTitle,
            memberCountLabel: viewModel.memberCountLabel,
            joinButtonTitle: viewModel.joinButtonTitle,
            isJoinEnabled: !viewModel.isOwner && !viewModel.isJoining,
            isJoining: viewModel.isJoining,
            onJoinTap: {
                Task { await viewModel.toggleMembership() }
            },
            onMembersTap: { viewModel.openMembers() },
            onInfoTap: { viewModel.openRoomInfo() },
            imagePipeline: imagePipeline
        )
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

                    if viewModel.showsEmpty {
                        ExperienceEmptyState(
                            icon: .rooms,
                            title: "No messages yet",
                            message: "Start the conversation in \(viewModel.selectedChannel?.displayTitle ?? "this channel")."
                        )
                        .padding(.top, ExperienceSpacing.xl)
                    }

                    ForEach(viewModel.timeline) { item in
                        switch item {
                        case .daySeparator(_, let title):
                            ConversationDaySeparatorView(title: title)
                        case .message(let bubble):
                            ConversationBubbleView(
                                item: bubble,
                                peerProfile: bubble.authorProfile,
                                imagePipeline: imagePipeline,
                                sharedTrade: viewModel.sharedTrade(for: bubble.message),
                                onRetry: {
                                    Task { await viewModel.retry(bubble) }
                                }
                            )
                            .padding(.vertical, 2)
                            .background {
                                if viewModel.highlightedMessageID == bubble.id {
                                    RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                                        .fill(colors.accent.opacity(0.16))
                                        .padding(.horizontal, ExperienceSpacing.xs)
                                        .transition(.opacity)
                                }
                            }
                            .animation(
                                ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
                                value: viewModel.highlightedMessageID
                            )
                            .id(bubble.id.rawValue)
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(RoomConversationScrollAnchor.bottom)
                }
                .padding(.vertical, ExperienceSpacing.sm)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.count) { _, _ in
                if viewModel.pendingScrollMessageID == nil {
                    scrollToBottom(proxy: proxy, animated: !reduceMotion)
                }
            }
            .onChange(of: viewModel.selectedChannelID) { _, _ in
                restoreScroll(proxy: proxy)
            }
            .onChange(of: viewModel.pendingScrollMessageID) { _, _ in
                restoreScroll(proxy: proxy)
            }
            .accessibilityIdentifier("tradeRooms.conversation.messageList")
        }
    }

    private func restoreScroll(proxy: ScrollViewProxy) {
        if let anchor = viewModel.pendingScrollMessageID {
            DispatchQueue.main.async {
                proxy.scrollTo(anchor.rawValue, anchor: .bottom)
                viewModel.clearPendingScroll()
            }
        } else {
            scrollToBottom(proxy: proxy, animated: false)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        let action = {
            proxy.scrollTo(RoomConversationScrollAnchor.bottom, anchor: .bottom)
        }
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

private enum RoomConversationScrollAnchor {
    static let bottom = "trade-room-scroll-bottom"
}
