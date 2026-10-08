import SwiftUI
import UIKit

/// Trade Room workspace — compact header + channel switcher + DM-style conversation.
struct RoomConversationView: View {
    @State private var viewModel: RoomConversationViewModel
    @State private var contentRevealed = false
    @State private var appliedScrollCommandGeneration: UInt64 = 0
    @State private var initialScrollRetryTask: Task<Void, Never>?
    @State private var settlingStabilityTask: Task<Void, Never>?
    @State private var lastScrollContentHeight: CGFloat = 0
    @State private var lastScrollSample: ConversationThreadScrollSupport.LayoutSample?
    @State private var userReleasedInitialPin = false
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
            } else if viewModel.showsJoinToSendPrompt {
                joinToSendBar
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
        .alert(
            viewModel.pendingDeleteMessage.map { viewModel.isOwnerModerationDelete($0) } == true
                ? "Delete this member's message?"
                : "Delete Message?",
            isPresented: $viewModel.showsDeleteMessageConfirmation
        ) {
            Button("Delete", role: .destructive) {
                Task { await viewModel.confirmDeleteMessage() }
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelDeleteMessage()
            }
        } message: {
            if let pending = viewModel.pendingDeleteMessage, viewModel.isOwnerModerationDelete(pending) {
                Text("This message will be permanently removed for everyone in this Trade Room.")
            } else {
                Text("This message will be removed for everyone in this Trade Room.")
            }
        }
        .sheet(item: $viewModel.managedMemberSheetItem) { member in
            RoomMemberManagementSheet(
                member: member,
                imagePipeline: imagePipeline,
                canRemove: viewModel.canRemoveMember(member),
                canBan: viewModel.canBanMember(member),
                onViewProfile: {
                    viewModel.managedMemberSheetItem = nil
                    viewModel.openProfile(member.id)
                },
                onRemove: {
                    viewModel.managedMemberSheetItem = nil
                    viewModel.requestMemberAction(.remove(member.id))
                },
                onBan: {
                    viewModel.managedMemberSheetItem = nil
                    viewModel.requestMemberAction(.ban(member.id))
                },
                onDismiss: { viewModel.managedMemberSheetItem = nil }
            )
        }
        .roomMemberModerationConfirmations(
            showsRemoveConfirmation: $viewModel.showsMemberActionConfirmation,
            showsBanConfirmation: $viewModel.showsBanMemberConfirmation,
            removeDialogTitle: conversationMemberActionDialogTitle,
            onConfirmRemove: { Task { await viewModel.confirmMemberAction() } },
            onConfirmBan: { Task { await viewModel.confirmMemberAction() } },
            onCancelRemove: { viewModel.pendingMemberAction = nil },
            onCancelBan: { viewModel.cancelBanMember() }
        )
        .alert(
            "Couldn't update member",
            isPresented: Binding(
                get: { viewModel.memberModerationErrorMessage != nil },
                set: { if !$0 { viewModel.memberModerationErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                viewModel.memberModerationErrorMessage = nil
            }
        } message: {
            Text(viewModel.memberModerationErrorMessage ?? "")
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
            resetInitialScrollSessionState()
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

    private var joinToSendBar: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            Text("Join this room to send messages")
                .experienceStyle(.subheadline, color: colors.secondaryText)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Task { await viewModel.toggleMembership() }
            } label: {
                Text(viewModel.joinButtonTitle)
                    .experienceStyle(.subheadline, color: colors.onAccent)
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.vertical, ExperienceSpacing.sm)
                    .background(colors.accent, in: Capsule())
            }
            .disabled(!viewModel.isJoinButtonEnabled)
            .opacity(viewModel.isJoinButtonEnabled ? 1 : 0.6)
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.vertical, ExperienceSpacing.sm)
        .background(colors.elevatedSurface)
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
                    if viewModel.hasMoreOlder, viewModel.isInitialScrollConfirmed {
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
                                    #if DEBUG
                                    SharedTradeOpenDiagnostics.tapped(tradeID: tradeID)
                                    #endif
                                    let preview =
                                        viewModel.sharedTrade(for: bubble.message)
                                        ?? viewModel.sharedTrades[tradeID]
                                    navigationCoordinator.pushSharedTrade(
                                        tradeID,
                                        host: navigationHost,
                                        cache: data.detailCache,
                                        preview: preview
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
                                guard viewModel.isInitialScrollPinningBottom else { return }
                                guard bubble.id == viewModel.newestMessageID else { return }
                                scrollToLatest(proxy: proxy, animated: false, reason: "newest-bubble-onAppear")
                            }
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(ConversationScrollAnchorID.bottom)
                        .onAppear {
                            guard viewModel.isInitialScrollPinningBottom else { return }
                            scrollToLatest(proxy: proxy, animated: false, reason: "bottom-anchor-onAppear")
                        }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, ExperienceSpacing.sm)
            }
            .defaultScrollAnchor(.bottom)
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
                            onManageUser: roomMessageManageAction(for: bubble),
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
                        onManageUser: roomMessageManageAction(for: bubble),
                        onReport: incomingRoomMessageReportAction(for: bubble),
                        onSelectEmoji: { emoji in
                            Task { await viewModel.toggleReaction(messageID: messageID, emoji: emoji) }
                        },
                        onDismiss: { actionMenuMessageID = nil }
                    )
                }
            }
            .simultaneousGesture(initialScrollReleaseGesture)
            .onScrollGeometryChange(for: ConversationThreadScrollSupport.ScrollGeometrySignal.self) { geometry in
                ConversationThreadScrollSupport.ScrollGeometrySignal(
                    contentHeight: geometry.contentSize.height,
                    contentOffsetY: geometry.contentOffset.y,
                    containerHeight: geometry.containerSize.height
                )
            } action: { previous, signal in
                let sample = signal.sample
                if viewModel.isInitialScrollPinningBottom {
                    if lastScrollSample.map({ ConversationThreadScrollSupport.geometrySignalsMatch($0, sample) }) != true {
                        lastScrollSample = sample
                    }
                    handleInitialScrollGeometry(sample, proxy: proxy)
                } else if viewModel.isInitialScrollConfirmed,
                          previous.sample.isNearBottom != sample.isNearBottom {
                    viewModel.scrollCoordinator.reportNearBottom(
                        sample.isNearBottom,
                        conversationID: viewModel.scrollScopeConversationID
                    )
                }
            }
            .onChange(of: viewModel.scrollCoordinator.scrollCommandGeneration) { _, _ in
                applyCoordinatorScrollCommand(proxy: proxy)
            }
            .onChange(of: viewModel.phase) { _, phase in
                guard phase == .loaded else { return }
                if viewModel.showsEmpty {
                    viewModel.confirmInitialScrollPositionForEmptyThread()
                } else if !viewModel.messages.isEmpty {
                    startInitialScrollPositioning(proxy: proxy, reason: "phase-loaded")
                }
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                guard viewModel.isInitialScrollPinningBottom else { return }
                guard !viewModel.messages.isEmpty else { return }
                startInitialScrollPositioning(proxy: proxy, reason: "messages-count")
            }
            .onChange(of: viewModel.sharedTrades.count) { _, _ in
                maintainInitialPinAfterRichContentHydration(proxy: proxy)
            }
            .onChange(of: viewModel.sharedPosts.count) { _, _ in
                maintainInitialPinAfterRichContentHydration(proxy: proxy)
            }
            .onChange(of: viewModel.sharedReels.count) { _, _ in
                maintainInitialPinAfterRichContentHydration(proxy: proxy)
            }
            .onChange(of: viewModel.sharedAchievements.count) { _, _ in
                maintainInitialPinAfterRichContentHydration(proxy: proxy)
            }
            .onChange(of: viewModel.selectedChannelID) { _, _ in
                resetInitialScrollSessionState()
            }
            .onChange(of: viewModel.pendingScrollMessageID) { _, messageID in
                guard viewModel.isInitialScrollConfirmed, let messageID else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(messageID.rawValue, anchor: .center)
                    viewModel.clearPendingScroll()
                }
            }
            .overlay(alignment: .bottom) {
                if viewModel.scrollCoordinator.showsNewMessagesIndicator {
                    newMessagesIndicator(proxy: proxy)
                }
            }
            .accessibilityIdentifier("tradeRooms.conversation.messageList")
            .onAppear {
                if viewModel.showsEmpty, viewModel.phase == .loaded {
                    viewModel.confirmInitialScrollPositionForEmptyThread()
                } else if !viewModel.messages.isEmpty, viewModel.phase == .loaded {
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
        viewModel.confirmInitialScrollPosition(userInitiatedRelease: true)
    }

    private func newMessagesIndicator(proxy: ScrollViewProxy) -> some View {
        Button {
            viewModel.scrollCoordinator.jumpToLatest(conversationID: viewModel.scrollScopeConversationID)
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
    }

    private func maintainInitialPinAfterRichContentHydration(proxy: ScrollViewProxy) {
        guard viewModel.initialScrollPhase == .settling else { return }
        guard let sample = lastScrollSample else { return }
        maintainInitialBottomPin(sample: sample, proxy: proxy, reason: "shared-content-hydrated")
        scheduleSettlingStabilityCheck(proxy: proxy)
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

    private func handleInitialScrollGeometry(
        _ sample: ConversationThreadScrollSupport.LayoutSample,
        proxy: ScrollViewProxy
    ) {
        let contentSizeDelta = sample.contentHeight - lastScrollContentHeight
        if abs(contentSizeDelta) >= 1 {
            lastScrollContentHeight = sample.contentHeight
        }

        switch viewModel.initialScrollPhase {
        case .pending:
            break
        case .positioning:
            guard sample.isNearBottom else { return }
            viewModel.beginInitialScrollSettling()
            scrollToLatest(proxy: proxy, animated: false, reason: "enter-settling")
            scheduleSettlingStabilityCheck(proxy: proxy)
        case .settling:
            if userReleasedInitialPin { return }
            if contentSizeDelta <= 1,
               sample.distanceFromBottom > ConversationThreadScrollSupport.userScrollReleaseThreshold
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
        sample: ConversationThreadScrollSupport.LayoutSample,
        proxy: ScrollViewProxy,
        reason: String
    ) {
        guard viewModel.initialScrollPhase == .settling else { return }
        guard !userReleasedInitialPin else { return }
        if sample.contentHeight > 0,
           (!sample.isNearBottom || sample.distanceFromBottom > ConversationThreadScrollSupport.bottomProximityThreshold / 2)
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
            try? await Task.sleep(nanoseconds: ConversationThreadScrollSupport.settlingStabilityDelayNs)
            guard !Task.isCancelled else { return }
            guard viewModel.initialScrollPhase == .settling else { return }
            guard !userReleasedInitialPin else { return }
            guard lastScrollContentHeight == baselineHeight else { return }
            guard lastScrollSample?.isNearBottom == true else { return }

            scrollToLatest(proxy: proxy, animated: false, reason: "settling-stable")
            viewModel.confirmInitialScrollPosition()
        }
    }

    private func scheduleInitialScrollRetries(proxy: ScrollViewProxy) {
        initialScrollRetryTask?.cancel()
        initialScrollRetryTask = Task { @MainActor in
            for attempt in 1...ConversationThreadScrollSupport.initialScrollRetryCount {
                guard !Task.isCancelled else { return }
                guard viewModel.isInitialScrollPinningBottom else { return }
                scrollToLatest(proxy: proxy, animated: false, reason: "retry-\(attempt)")
                try? await Task.sleep(nanoseconds: ConversationThreadScrollSupport.initialScrollRetryIntervalNs)
            }
            guard !Task.isCancelled else { return }
            guard viewModel.isInitialScrollPinningBottom else { return }
            viewModel.confirmInitialScrollPosition()
        }
    }

    private func scrollToLatest(proxy: ScrollViewProxy, animated: Bool, reason: String) {
        #if DEBUG
        ConversationThreadScrollActions.scrollToLatest(
            proxy: proxy,
            newestMessageID: viewModel.newestMessageID,
            timelineContainsTarget: threadTimelineContainsScrollTarget,
            animated: animated,
            reduceMotion: reduceMotion,
            reason: reason,
            conversationID: viewModel.scrollScopeConversationID,
            debugContext: ConversationScrollDiagnostics.ScrollAttemptContext(
                firstMessageID: viewModel.messages.first?.id,
                lastMessageID: viewModel.messages.last?.id,
                initialScrollPhase: String(describing: viewModel.initialScrollPhase),
                phase: String(describing: viewModel.phase),
                messageCount: viewModel.messages.count,
                hasMoreOlder: viewModel.hasMoreOlder
            )
        )
        #else
        ConversationThreadScrollActions.scrollToLatest(
            proxy: proxy,
            newestMessageID: viewModel.newestMessageID,
            timelineContainsTarget: threadTimelineContainsScrollTarget,
            animated: animated,
            reduceMotion: reduceMotion,
            reason: reason,
            conversationID: viewModel.scrollScopeConversationID
        )
        #endif
    }

    private func threadTimelineContainsScrollTarget(_ target: String) -> Bool {
        viewModel.timeline.contains { item in
            if case .message(let bubble) = item {
                return bubble.id.rawValue == target
            }
            return target == ConversationScrollAnchorID.bottom
        }
    }

    private func applyCoordinatorScrollCommand(proxy: ScrollViewProxy) {
        ConversationThreadScrollActions.applyCoordinatorScrollCommand(
            proxy: proxy,
            coordinator: viewModel.scrollCoordinator,
            appliedGeneration: &appliedScrollCommandGeneration,
            reduceMotion: reduceMotion,
            isInitialScrollConfirmed: viewModel.isInitialScrollConfirmed
        )
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

    private var conversationMemberActionDialogTitle: String {
        guard let action = viewModel.pendingMemberAction else { return "" }
        return viewModel.memberActionTitle(for: action)
    }

    private func roomMessageManageAction(for bubble: ConversationBubbleItem) -> (() -> Void)? {
        guard viewModel.canManageMessageMember(bubble) else { return nil }
        return {
            actionMenuMessageID = nil
            viewModel.requestManageMember(bubble)
        }
    }
}
