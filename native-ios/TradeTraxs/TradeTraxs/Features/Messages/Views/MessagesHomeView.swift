import SwiftUI

/// Permanent Messages home, Direct Messages + Trade Rooms foundation.
struct MessagesHomeView: View {
    @State private var viewModel: MessagesHomeViewModel
    @Bindable private var inboxStore = MessagesInboxStore.shared
    private let imagePipeline: any ImagePipeline
    private let data: DataEnvironment

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.tabIsActive) private var tabIsActive

    @State private var tradeRoomsSectionExpanded = false
    @State private var directMessagesSectionExpanded = false

    private enum InboxSectionPreview {
        static let limit = 4
    }

    init(
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator
    ) {
        _viewModel = State(
            initialValue: MessagesHomeViewModel(
                messages: data.messages,
                rooms: data.rooms,
                profiles: data.profiles,
                session: data.session,
                detailCache: data.detailCache,
                navigationCoordinator: navigationCoordinator,
                realtimeHub: data.realtimeHub,
                rpc: data.rpc
            )
        )
        self.imagePipeline = data.imagePipeline
        self.data = data
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle, .loading:
                if inboxStore.hasLoaded {
                    inboxList
                } else {
                    MessagesInboxSkeleton()
                }
            case .failed(let message):
                if inboxStore.hasLoaded {
                    inboxList
                } else {
                    ExperienceErrorState(
                        title: "Couldn't load messages",
                        message: message,
                        onRetry: { Task { await viewModel.refresh() } }
                    )
                }
            case .loaded where ExploreModeSupport.skipsAuthenticatedViewerServices:
                guestMessagesUnavailableState
                    .experienceScreenContentAreaFill(alignment: .center)
            case .loaded where viewModel.showsEmpty:
                messagesEmptyState
                    .experienceScreenContentAreaFill(alignment: .center)
            case .loaded:
                inboxList
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Messages")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    viewModel.openSettings()
                } label: {
                    ExperienceIcon(icon: .settings, size: .md, color: colors.primaryText)
                }
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("messages.settings")
            }
            if !ExploreModeSupport.isActive {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.presentNewChat()
                    } label: {
                        ExperienceIcon(icon: .compose, size: .md, color: colors.accent)
                    }
                    .accessibilityLabel("New Chat")
                    .accessibilityIdentifier("messages.newChat")
                }
            }
        }
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search messages"
        )
        .refreshable {
            await viewModel.refresh()
        }
        .task(id: tabIsActive) {
            guard tabIsActive else {
                viewModel.setHomeScreenVisible(false)
                viewModel.releaseRealtime()
                SupabasePressureLog.screenRealtimeTransition(
                    screen: "messages",
                    active: false,
                    snapshot: data.realtimeHub.realtimePressureSnapshot()
                )
                return
            }
#if DEBUG
            SafeInboxLog.storeObserved(instance: inboxStore.debugInstance, source: "MessagesHomeView")
#endif
            ActiveScreenBootstrapPriorityGate.messages.setScreenActive(true)
            viewModel.setHomeScreenVisible(true)
            defer {
                ActiveScreenBootstrapPriorityGate.messages.setScreenActive(false)
                viewModel.setHomeScreenVisible(false)
                viewModel.releaseRealtime()
                SupabasePressureLog.screenRealtimeTransition(
                    screen: "messages",
                    active: false,
                    snapshot: data.realtimeHub.realtimePressureSnapshot()
                )
            }
            await viewModel.bootstrapIfNeeded()
            SupabasePressureLog.screenRealtimeTransition(
                screen: "messages",
                active: true,
                snapshot: data.realtimeHub.realtimePressureSnapshot()
            )
        }
        .sheet(isPresented: $viewModel.showsNewChat) {
            NewChatPickerView(data: data) { conversation in
                viewModel.handleCreatedConversation(conversation)
            }
            .experienceSheetChrome()
        }
        .alert("Delete Conversation?", isPresented: $viewModel.showsDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                viewModel.cancelDeleteConversation()
            }
            Button(
                viewModel.isDeletingConversation ? "Deleting…" : "Delete",
                role: .destructive
            ) {
                guard let id = viewModel.pendingDeleteConversationID else { return }
                Task { await viewModel.confirmDeleteConversation(id: id) }
            }
            .disabled(viewModel.isDeletingConversation)
        } message: {
            Text("This will remove this conversation from your messages.")
        }
        .alert(
            "Couldn't Delete Conversation",
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
        .confirmationDialog(
            "Leave this Trade Room?",
            isPresented: Binding(
                get: { viewModel.showsLeaveRoomConfirmation },
                set: { presented in
                    if !presented { viewModel.cancelLeaveRoom() }
                }
            ),
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
    }

    private var inboxList: some View {
        // Observe canonical inbox activity, preview text, sort order, and unread.
        let _ = inboxStore.activityRevision
        let orderSignature = inboxStore.visibleConversations.map {
            "\($0.id.rawValue)|\($0.lastMessageAt?.timeIntervalSince1970 ?? 0)|\($0.lastMessagePreview ?? "")|\($0.lastMessageID?.rawValue ?? "")"
        }
        return List {
            if viewModel.showsFilteredEmpty {
                Section {
                    ExperienceEmptyState(
                        icon: .search,
                        title: "No matches",
                        message: "Try a different name or room."
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }

            if !viewModel.pinnedItems.isEmpty {
                Section {
                    ForEach(viewModel.pinnedItems) { item in
                        conversationButton(item)
                            .messagesInboxConversationListRowStyle(
                                colors: colors,
                                showsBottomSeparator: item.id != viewModel.pinnedItems.last?.id
                            )
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                dmTrailingActions(item)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                dmLeadingActions(item)
                            }
                            .contextMenu { dmContextMenu(item) } preview: {
                                conversationPreview(item)
                            }
                    }
                } header: {
                    messagesInboxSectionHeader("Pinned")
                }
            }

            if let ownedRoom = viewModel.ownedTradeRoomItem {
                Section {
                    tradeRoomRow(ownedRoom, showsBottomSeparator: false)
                }
            }

            if !viewModel.directMessageItems.isEmpty {
                Section {
                    ForEach(displayedDirectMessageItems) { item in
                        conversationButton(item)
                            .messagesInboxConversationListRowStyle(
                                colors: colors,
                                showsBottomSeparator: showsBottomSeparatorAfterInboxRow(
                                    itemID: item.id,
                                    lastItemID: displayedDirectMessageItems.last?.id,
                                    sectionHasTrailingToggle: showsDirectMessagesSectionToggle
                                )
                            )
                            .onAppear {
                                if item.id == displayedDirectMessageItems.last?.id,
                                   directMessagesSectionExpanded || !showsDirectMessagesSectionToggle
                                {
                                    Task { await viewModel.loadMoreInboxIfNeeded() }
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                dmTrailingActions(item)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                dmLeadingActions(item)
                            }
                            .contextMenu { dmContextMenu(item) } preview: {
                                conversationPreview(item)
                            }
                    }
                    if showsDirectMessagesSectionToggle {
                        inboxSectionToggle(expanded: $directMessagesSectionExpanded)
                    }
                } header: {
                    messagesInboxSectionHeader("Direct Messages")
                        .padding(
                            .top,
                            viewModel.ownedTradeRoomItem != nil
                                ? -MessagesInboxLayout.directMessagesHeaderTopCompression
                                : 0
                        )
                }
            }

            if !viewModel.joinedTradeRoomItems.isEmpty {
                Section {
                    ForEach(displayedJoinedTradeRoomItems) { item in
                        tradeRoomRow(
                            item,
                            showsBottomSeparator: showsBottomSeparatorAfterInboxRow(
                                itemID: item.id,
                                lastItemID: displayedJoinedTradeRoomItems.last?.id,
                                sectionHasTrailingToggle: showsJoinedTradeRoomsSectionToggle
                            )
                        )
                    }
                    if showsJoinedTradeRoomsSectionToggle {
                        inboxSectionToggle(expanded: $tradeRoomsSectionExpanded)
                    }
                } header: {
                    messagesTradeRoomsSectionHeader
                }
            }
        }
        .listSectionSpacing(MessagesInboxLayout.sectionSpacing)
        .contentMargins(.top, MessagesInboxLayout.listTopContentMargin, for: .scrollContent)
        .experienceInsetGroupedListStyle(pageBackground: false)
        .scrollDismissesKeyboard(.interactively)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: viewModel.searchText)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: orderSignature)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: inboxStore.activityRevision)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: tradeRoomsSectionExpanded)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: directMessagesSectionExpanded)
    }

    private var displayedJoinedTradeRoomItems: [TradeRoomInboxItem] {
        previewSlice(viewModel.joinedTradeRoomItems, expanded: tradeRoomsSectionExpanded)
    }

    private var displayedDirectMessageItems: [DirectMessageInboxItem] {
        previewSlice(viewModel.directMessageItems, expanded: directMessagesSectionExpanded)
    }

    private var showsJoinedTradeRoomsSectionToggle: Bool {
        viewModel.joinedTradeRoomItems.count > InboxSectionPreview.limit
    }

    private func showsBottomSeparatorAfterInboxRow<ID: Equatable>(
        itemID: ID,
        lastItemID: ID?,
        sectionHasTrailingToggle: Bool
    ) -> Bool {
        guard itemID == lastItemID else { return true }
        return !sectionHasTrailingToggle
    }

    @ViewBuilder
    private func tradeRoomRow(_ item: TradeRoomInboxItem, showsBottomSeparator: Bool) -> some View {
        Button {
            viewModel.openRoom(item)
        } label: {
            TradeRoomInboxRowView(item: item, imagePipeline: imagePipeline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.experiencePlain)
        .messagesInboxConversationListRowStyle(
            colors: colors,
            showsBottomSeparator: showsBottomSeparator
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            roomTrailingActions(item)
        }
        .contextMenu { roomContextMenu(item) } preview: {
            roomPreview(item)
        }
    }

    private var showsDirectMessagesSectionToggle: Bool {
        viewModel.directMessageItems.count > InboxSectionPreview.limit
    }

    private func previewSlice<T>(_ items: [T], expanded: Bool) -> [T] {
        guard !expanded, items.count > InboxSectionPreview.limit else { return items }
        return Array(items.prefix(InboxSectionPreview.limit))
    }

    private func messagesInboxSectionHeader(_ title: String) -> some View {
        Text(title)
            .padding(.bottom, -MessagesInboxLayout.headerToFirstRowCompression)
    }

    private var messagesTradeRoomsSectionHeader: some View {
        HStack(spacing: ExperienceSpacing.xs) {
            ExperienceIcon(icon: .rooms, size: .sm, color: colors.accent)
            Text("Trade Rooms")
        }
        .padding(.bottom, -MessagesInboxLayout.headerToFirstRowCompression)
    }

    private func inboxSectionToggle(expanded: Binding<Bool>) -> some View {
        Button {
            expanded.wrappedValue.toggle()
        } label: {
            Text(expanded.wrappedValue ? "Show Less" : "Show More")
                .experienceStyle(.subheadline, color: colors.accent)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, MessagesInboxLayout.sectionToggleVerticalPadding)
        }
        .buttonStyle(.experiencePlain)
        .messagesInboxSectionToggleRowStyle(colors: colors)
        .accessibilityLabel(expanded.wrappedValue ? "Show less" : "Show more")
    }

    private func conversationButton(_ item: DirectMessageInboxItem) -> some View {
        Button {
            viewModel.openConversation(item)
        } label: {
            ConversationRowView(item: item, imagePipeline: imagePipeline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.experiencePlain)
    }

    @ViewBuilder
    private func dmLeadingActions(_ item: DirectMessageInboxItem) -> some View {
        Button {
            viewModel.toggleRead(conversationID: item.id)
        } label: {
            Label(
                item.unreadCount > 0 ? "Read" : "Unread",
                systemImage: item.unreadCount > 0 ? "message" : "envelope.badge"
            )
        }
        .tint(colors.info)
    }

    @ViewBuilder
    private func dmTrailingActions(_ item: DirectMessageInboxItem) -> some View {
        Button(role: .destructive) {
            viewModel.requestDeleteConversation(id: item.id)
        } label: {
            Label("Delete", systemImage: "trash")
        }
        Button {
            viewModel.toggleMute(conversationID: item.id)
        } label: {
            Label(
                item.isMuted ? "Unmute" : "Mute",
                systemImage: item.isMuted ? "bell.fill" : "bell.slash.fill"
            )
        }
        .tint(colors.warning)
        Button {
            viewModel.togglePin(conversationID: item.id)
        } label: {
            Label(
                item.isPinned ? "Unpin" : "Pin",
                systemImage: item.isPinned ? "pin.slash.fill" : "pin.fill"
            )
        }
        .tint(colors.accent)
    }

    @ViewBuilder
    private func dmContextMenu(_ item: DirectMessageInboxItem) -> some View {
        Button {
            viewModel.openConversation(item)
        } label: {
            Label("Open", systemImage: "bubble.left.and.bubble.right")
        }
        Button {
            viewModel.toggleRead(conversationID: item.id)
        } label: {
            Label(
                item.unreadCount > 0 ? "Mark as Read" : "Mark as Unread",
                systemImage: item.unreadCount > 0 ? "envelope.open" : "envelope.badge"
            )
        }
        Button {
            viewModel.togglePin(conversationID: item.id)
        } label: {
            Label(
                item.isPinned ? "Unpin" : "Pin",
                systemImage: item.isPinned ? "pin.slash" : "pin"
            )
        }
        Button {
            viewModel.toggleMute(conversationID: item.id)
        } label: {
            Label(
                item.isMuted ? "Unmute" : "Mute",
                systemImage: item.isMuted ? "bell" : "bell.slash"
            )
        }
        Divider()
        Button(role: .destructive) {
            viewModel.requestDeleteConversation(id: item.id)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func roomTrailingActions(_ item: TradeRoomInboxItem) -> some View {
        if !viewModel.isViewerOwner(of: item.room) {
            Button(role: .destructive) {
                viewModel.requestLeaveRoom(id: item.id)
            } label: {
                Label("Leave Room", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
        Button {
            viewModel.toggleMute(roomID: item.id)
        } label: {
            Label(
                item.isMuted ? "Unmute" : "Mute",
                systemImage: item.isMuted ? "bell.fill" : "bell.slash.fill"
            )
        }
        .tint(colors.warning)
    }

    @ViewBuilder
    private func roomContextMenu(_ item: TradeRoomInboxItem) -> some View {
        Button {
            viewModel.openRoom(item)
        } label: {
            Label("Open", systemImage: "person.3")
        }
        Button {
            viewModel.toggleMute(roomID: item.id)
        } label: {
            Label(
                item.isMuted ? "Unmute" : "Mute",
                systemImage: item.isMuted ? "bell" : "bell.slash"
            )
        }
        if !viewModel.isViewerOwner(of: item.room) {
            Divider()
            Button(role: .destructive) {
                viewModel.requestLeaveRoom(id: item.id)
            } label: {
                Label("Leave Room", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
    }

    private func conversationPreview(_ item: DirectMessageInboxItem) -> some View {
        ConversationRowView(item: item, imagePipeline: imagePipeline)
            .padding()
            .frame(width: 320)
            .messagesInboxConversationPreviewBackground(colors: colors)
    }

    private func roomPreview(_ item: TradeRoomInboxItem) -> some View {
        TradeRoomInboxRowView(item: item, imagePipeline: imagePipeline)
            .padding()
            .frame(width: 320)
            .messagesInboxConversationPreviewBackground(colors: colors)
    }

    private var messagesEmptyState: some View {
        VStack(spacing: ExperienceSpacing.xs) {
            ExperienceIcon(icon: .messages, size: .md, color: colors.tertiaryText)

            Text("No conversations yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colors.primaryText)
                .multilineTextAlignment(.center)

            Text("Start a conversation with another trader.")
                .font(.caption)
                .foregroundStyle(colors.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("Start a Conversation") {
                ExperienceHaptics.play(.selection)
                viewModel.presentNewChat()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(colors.accent)
            .padding(.top, ExperienceSpacing.xxs)

            Text("Or")
                .font(.caption)
                .foregroundStyle(colors.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, ExperienceSpacing.xxs)

            Button("Explore Trade Rooms") {
                ExperienceHaptics.play(.selection)
                viewModel.exploreTradeRooms()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(colors.accent)
            .accessibilityIdentifier("messages.emptyState.exploreTradeRooms")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ExperienceSpacing.md)
        .accessibilityElement(children: .contain)
        .experienceAccessibility(
            label: "No conversations yet",
            hint: "Start a conversation with another trader.",
            identifier: "messages.emptyState"
        )
    }

    private var guestMessagesUnavailableState: some View {
        VStack(spacing: ExperienceSpacing.sm) {
            ExperienceIcon(icon: .messages, size: .md, color: colors.tertiaryText)
            Text("Messages require an account")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colors.primaryText)
            Text("Guest Mode can explore public Feed, profiles, and the showcase journal. Sign in to message other traders.")
                .font(.caption)
                .foregroundStyle(colors.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            ExperienceButton(
                title: "Create Account",
                kind: .primary,
                accessibilityIdentifier: "messages.guest.createAccount"
            ) {
                AppLaunchController.shared.exitDemoExplore(authIntent: .createAccount)
            }
            .padding(.top, ExperienceSpacing.xs)
        }
        .padding(.horizontal, ExperienceSpacing.lg)
        .accessibilityIdentifier("messages.guest.unavailable")
    }
}

// MARK: - Shared inbox row chrome (DM + Trade Room)

private extension View {
    /// Inset grouped list row, matches Direct Messages and Trade Rooms on Messages home.
    func messagesInboxConversationListRowStyle(
        colors: SemanticColorPalette,
        showsBottomSeparator: Bool = true
    ) -> some View {
        listRowBackground(colors.backgroundPrimary)
            .listRowSeparator(showsBottomSeparator ? .visible : .hidden, edges: .bottom)
            .listRowSeparatorTint(
                colors.separator.opacity(MessagesInboxLayout.rowSeparatorLineOpacity)
            )
            .alignmentGuide(.listRowSeparatorLeading) { _ in
                MessagesInboxLayout.rowSeparatorHorizontalInset
            }
            .alignmentGuide(.listRowSeparatorTrailing) { dimensions in
                dimensions[.trailing] - MessagesInboxLayout.rowSeparatorHorizontalInset
            }
    }

    func messagesInboxSectionToggleRowStyle(colors: SemanticColorPalette) -> some View {
        listRowBackground(colors.backgroundPrimary)
            .listRowSeparator(.hidden)
            .listRowInsets(
                EdgeInsets(
                    top: 0,
                    leading: 0,
                    bottom: 0,
                    trailing: 0
                )
            )
    }

    func messagesInboxConversationPreviewBackground(colors: SemanticColorPalette) -> some View {
        background(colors.backgroundPrimary)
    }
}
