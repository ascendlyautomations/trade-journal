import SwiftUI

/// Trade Room workspace — compact header + channel switcher + DM-style conversation.
struct RoomConversationView: View {
    @State private var viewModel: RoomConversationViewModel
    @State private var contentRevealed = false
    @State private var didApplyInitialScrollToLatest = false
    @State private var actionMenuMessageID: MessageID?
    private let imagePipeline: any ImagePipeline
    private let data: DataEnvironment?
    private let navigationCoordinator: NavigationCoordinator?
    private let navigationHost: TradeRoomNavigationHost

    @Environment(\.themeColors) private var colors
    @Environment(\.appEnvironment) private var appEnvironment
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
                feed: data.feed,
                achievements: data.achievements,
                notifications: data.notifications,
                rpc: data.rpc,
                navigationCoordinator: navigationCoordinator,
                navigationHost: navigationHost,
                realtimeHub: data.realtimeHub,
                messages: data.messages
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
                if viewModel.showsActivePresence {
                    RoomActivePresenceBar(
                        members: viewModel.activePresenceMembers,
                        imagePipeline: imagePipeline,
                        onTap: { viewModel.openActivePresence() }
                    )
                }
                if !viewModel.channels.isEmpty {
                    RoomChannelSwitcherView(
                        channels: viewModel.channels,
                        selectedChannelID: viewModel.selectedChannelID,
                        onSelect: { viewModel.selectChannel($0) }
                    )
                }
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            if let deleteErrorMessage = viewModel.deleteErrorMessage {
                Text(deleteErrorMessage)
                    .experienceStyle(.caption, color: colors.error)
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.vertical, ExperienceSpacing.xs)
            }
            if viewModel.shouldShowMessageComposer {
                MessageComposerBar(
                    draft: $viewModel.draft,
                    isSending: viewModel.isSending,
                    isEnabled: viewModel.canPostInSelectedChannel,
                    placeholder: composerPlaceholder,
                    onSend: {
                        Task { await viewModel.sendText() }
                    },
                    onSendImage: { image in
                        Task { await viewModel.sendImage(image) }
                    },
                    onSendVoice: { url, duration in
                        Task { await viewModel.sendVoice(localFileURL: url, duration: duration) }
                    },
                    onSendTrade: {
                        viewModel.presentTradePicker()
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .experienceScreenBackground(fillsContentArea: false)
        .experienceNavigationTitle(viewModel.title)
        .toolbar(.hidden, for: .tabBar)
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
                if viewModel.canManageRoom {
                    Button {
                        viewModel.openManageRoom()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(colors.primaryText)
                    }
                    .experienceTouchTarget()
                    .accessibilityLabel("Manage Room")
                    .accessibilityIdentifier("tradeRooms.conversation.manage")
                } else if viewModel.isMember {
                    Menu {
                        Button(
                            "Leave Room",
                            systemImage: "rectangle.portrait.and.arrow.right",
                            role: .destructive
                        ) {
                            viewModel.requestLeaveRoom()
                        }
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
        }
        .sheet(isPresented: $viewModel.showsTradePicker) {
            TradeSharePickerSheet(
                trades: viewModel.tradePickerTrades,
                imagePipeline: imagePipeline,
                isLoading: viewModel.isLoadingTradePicker,
                onSelect: { trade in
                    Task { await viewModel.sendTrade(trade) }
                },
                onClose: { viewModel.showsTradePicker = false }
            )
            .task { await viewModel.loadTradePickerIfNeeded() }
        }
        .sheet(isPresented: $viewModel.showsActivePresenceSheet) {
            RoomActivePresenceSheet(
                members: viewModel.activePresenceMembers,
                imagePipeline: imagePipeline,
                onSelectProfile: { profileID in
                    viewModel.closeActivePresence()
                    viewModel.openProfile(profileID)
                },
                onClose: { viewModel.closeActivePresence() }
            )
        }
        .alert("Delete Message?", isPresented: $viewModel.showsDeleteMessageConfirmation) {
            Button("Delete", role: .destructive) {
                Task { await viewModel.confirmDeleteMessage() }
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelDeleteMessage()
            }
        } message: {
            Text("This message will be removed for everyone in this Trade Room.")
        }
        .confirmationDialog(
            "Leave this Trade Room?",
            isPresented: $viewModel.showsLeaveRoomConfirmation,
            titleVisibility: .visible
        ) {
            Button("Leave Room", role: .destructive) {
                Task { await viewModel.confirmLeaveRoom() }
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelLeaveRoom()
            }
        } message: {
            Text("You can rejoin later if the room is still available.")
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
            didApplyInitialScrollToLatest = false
            viewModel.loadIfNeeded()
        }
        .onDisappear {
            viewModel.stopRealtime()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tradeRoomMetadataDidChange)) { notification in
            guard let changedID = notification.object as? RoomID,
                  changedID == viewModel.roomID
            else { return }
            Task { await viewModel.reloadRoomMetadataIfNeeded() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tradeRoomChannelsDidChange)) { notification in
            guard let changedID = notification.object as? RoomID,
                  changedID == viewModel.roomID
            else { return }
            Task { await viewModel.reloadChannelsIfNeeded() }
        }
    }

    private var composerPlaceholder: String {
        if !viewModel.canPostInSelectedChannel {
            return "Owner announcements only"
        }
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
            if viewModel.showsJoinPreviewPlaceholder {
                ExperienceEmptyState(
                    icon: .rooms,
                    title: "Members only",
                    message: viewModel.joinPreviewMessage
                )
            } else if viewModel.channels.isEmpty {
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
            showsJoinButton: viewModel.showsJoinButton,
            isJoinEnabled: viewModel.isJoinButtonEnabled,
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
                                peerProfile: viewModel.senderProfile(for: bubble.message.senderProfileID),
                                imagePipeline: imagePipeline,
                                sharedTrade: viewModel.sharedTrade(for: bubble.message),
                                sharedPost: viewModel.sharedPost(for: bubble.message),
                                sharedPostAuthor: viewModel.sharedPost(for: bubble.message)
                                    .map { viewModel.authorProfile(for: $0.authorProfileID) } ?? nil,
                                sharedReel: viewModel.sharedReel(for: bubble.message),
                                sharedReelAuthor: viewModel.sharedReel(for: bubble.message)
                                    .map { viewModel.authorProfile(for: $0.authorProfileID) } ?? nil,
                                sharedAchievement: viewModel.sharedAchievement(for: bubble.message),
                                sharedAchievementAuthor: viewModel.sharedAchievement(for: bubble.message)
                                    .map { viewModel.authorProfile(for: $0.ownerProfileID) } ?? nil,
                                isSharedContentUnavailable: viewModel.isSharedContentUnavailable(bubble.message),
                                reactionConfiguration: viewModel.reactionConfiguration(for: bubble.message),
                                onLongPressForActionMenu: {
                                    actionMenuMessageID = bubble.id
                                },
                                isActionMenuAnchorActive: actionMenuMessageID == bubble.id,
                                canDelete: viewModel.canDeleteMessage(bubble),
                                deleteMenuTitle: "Delete Message",
                                onRetry: {
                                    Task { await viewModel.retry(bubble) }
                                },
                                onDelete: {
                                    viewModel.requestDeleteMessage(bubble)
                                },
                                onSharedTradeTap: { tradeID in
                                    guard let navigationCoordinator, let data else { return }
                                    navigationCoordinator.pushSharedTrade(
                                        tradeID,
                                        host: navigationHost,
                                        cache: data.detailCache
                                    )
                                },
                                onSharedContentTap: { reference in
                                    guard let data else { return }
                                    SharedContentNavigation.open(
                                        reference: reference,
                                        cache: data.detailCache,
                                        coordinator: navigationCoordinator,
                                        host: navigationHost
                                    )
                                },
                                onSharedStoryTap: { payload in
                                    guard let data else { return }
                                    StoryShareNavigation.open(
                                        payload: payload,
                                        cache: data.detailCache,
                                        coordinator: navigationCoordinator
                                    )
                                },
                                onReport: incomingRoomMessageReportAction(for: bubble),
                                onSenderAvatarTap: { profileID in
                                    viewModel.openProfile(profileID)
                                }
                            )
                            .padding(
                                .top,
                                bubble.addsSenderGroupTopInset
                                    ? ExperienceSpacing.sm
                                    : (bubble.startsSenderGroup ? ExperienceSpacing.xxs : 0)
                            )
                            .padding(.bottom, bubble.startsSenderGroup ? ExperienceSpacing.xxs : 0)
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
                            .onAppear {
                                if bubble.id == viewModel.newestMessageID, !didApplyInitialScrollToLatest {
                                    didApplyInitialScrollToLatest = true
                                    scrollToLatest(proxy: proxy, animated: false)
                                }
                            }
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(RoomConversationScrollAnchor.bottom)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, ExperienceSpacing.sm)
            }
            .scrollDismissesKeyboard(.interactively)
            .messageBubbleActionMenuOverlay(
                activeMessageID: $actionMenuMessageID,
                menuSize: { messageID in
                    guard let bubble = viewModel.bubbleItem(for: messageID) else { return .zero }
                    let reactions = viewModel.reactionConfiguration(for: bubble.message)
                    return MessageBubbleActionMenuSupport.estimatedMenuSize(
                        emojiCount: MessageBubbleActionMenuSupport.emojiCount(
                            item: bubble,
                            reactionConfiguration: reactions
                        ),
                        actionCount: MessageBubbleActionMenuSupport.actionCount(
                            item: bubble,
                            reactionConfiguration: reactions,
                            canDelete: viewModel.canDeleteMessage(bubble),
                            onRetry: { Task { await viewModel.retry(bubble) } },
                            onReport: incomingRoomMessageReportAction(for: bubble)
                        )
                    )
                }
            ) { messageID in
                if let bubble = viewModel.bubbleItem(for: messageID) {
                    let reactions = viewModel.reactionConfiguration(for: bubble.message)
                    MessageBubbleActionMenuSupport.menu(
                        item: bubble,
                        reactionConfiguration: reactions,
                        canDelete: viewModel.canDeleteMessage(bubble),
                        deleteMenuTitle: "Delete Message",
                        onRetry: { Task { await viewModel.retry(bubble) } },
                        onDelete: { viewModel.requestDeleteMessage(bubble) },
                        onReport: incomingRoomMessageReportAction(for: bubble),
                        onSelectEmoji: { emoji in
                            Task { await viewModel.toggleReaction(messageID: messageID, emoji: emoji) }
                        },
                        onDismiss: { actionMenuMessageID = nil }
                    )
                }
            }
            .onChange(of: viewModel.phase) { _, phase in
                guard phase == .loaded, !didApplyInitialScrollToLatest else { return }
                // Non-empty threads wait for the newest bubble's onAppear before scrolling.
                guard viewModel.showsEmpty else { return }
                didApplyInitialScrollToLatest = true
                scrollToLatest(proxy: proxy, animated: false)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if viewModel.pendingScrollMessageID == nil, didApplyInitialScrollToLatest {
                    scrollToLatest(proxy: proxy, animated: !reduceMotion)
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
            scrollToLatest(proxy: proxy, animated: false)
        }
    }

    private func scrollToLatest(proxy: ScrollViewProxy, animated: Bool) {
        let action = {
            if let newest = viewModel.newestMessageID?.rawValue {
                proxy.scrollTo(newest, anchor: .bottom)
            } else {
                proxy.scrollTo(RoomConversationScrollAnchor.bottom, anchor: .bottom)
            }
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

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        scrollToLatest(proxy: proxy, animated: animated)
    }

    private func incomingRoomMessageReportAction(for bubble: ConversationBubbleItem) -> (() -> Void)? {
        guard !bubble.isOutgoing,
              bubble.message.senderProfileID != viewModel.viewerID
        else { return nil }
        return {
            ExperienceHaptics.play(.selection)
            ContentReportSupport.presentTradeRoomMessage(
                message: bubble.message,
                presenter: appEnvironment.contentReportPresenter
            )
        }
    }
}

private enum RoomConversationScrollAnchor {
    static let bottom = "trade-room-scroll-bottom"
}
