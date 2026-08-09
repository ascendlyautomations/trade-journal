import SwiftUI

/// Permanent Messages home — Direct Messages + Trade Rooms foundation.
struct MessagesHomeView: View {
    @State private var viewModel: MessagesHomeViewModel
    private let imagePipeline: any ImagePipeline
    private let data: DataEnvironment

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                realtimeHub: data.realtimeHub
            )
        )
        self.imagePipeline = data.imagePipeline
        self.data = data
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle, .loading:
                if MessagesInboxStore.shared.hasLoaded {
                    inboxList
                } else {
                    MessagesInboxSkeleton()
                }
            case .failed(let message):
                if MessagesInboxStore.shared.hasLoaded {
                    inboxList
                } else {
                    ExperienceErrorState(
                        title: "Couldn't load messages",
                        message: message,
                        onRetry: { Task { await viewModel.refresh() } }
                    )
                }
            case .loaded where viewModel.showsEmpty:
                ExperienceEmptyState(
                    icon: .messages,
                    title: "No conversations yet.",
                    message: "Start a conversation with another trader.",
                    actionTitle: "Start a Conversation",
                    action: { viewModel.presentNewChat() }
                )
            case .loaded:
                inboxList
            }
        }
        .experienceScreenBackground()
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.large)
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
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search messages"
        )
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            viewModel.loadIfNeeded()
        }
        .sheet(isPresented: $viewModel.showsNewChat) {
            NewChatPickerView(data: data) { conversation in
                viewModel.handleCreatedConversation(conversation)
            }
        }
        .alert(
            "Delete Chat",
            isPresented: Binding(
                get: { viewModel.showsDeleteConfirmation },
                set: { presented in
                    if presented {
                        viewModel.showsDeleteConfirmation = true
                    } else {
                        viewModel.cancelDeleteConversation()
                    }
                }
            )
        ) {
            Button("Cancel", role: .cancel) {
                viewModel.cancelDeleteConversation()
            }
            Button(
                viewModel.isDeletingConversation ? "Deleting…" : "Delete Chat",
                role: .destructive
            ) {
                Task { await viewModel.confirmDeleteConversation() }
            }
            .disabled(viewModel.isDeletingConversation)
        } message: {
            Text("Are you sure you want to permanently delete this conversation? This action cannot be undone.")
        }
    }

    private var inboxList: some View {
        // Observe shared inbox so send/realtime/read patches refresh rows without a full reload.
        // Track DM + Trade Room unread — unread-only mutations previously left badges sticky.
        let _ = MessagesInboxStore.shared.conversations.map { ($0.unreadCount, $0.lastMessageAt) }
        let _ = MessagesInboxStore.shared.roomUnread
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
                Section("Pinned") {
                    ForEach(viewModel.pinnedItems) { item in
                        conversationButton(item)
                            .listRowBackground(colors.backgroundPrimary)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                dmTrailingActions(item)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                dmLeadingActions(item)
                            }
                    }
                }
            }

            if !viewModel.directMessageItems.isEmpty {
                Section("Direct Messages") {
                    ForEach(viewModel.directMessageItems) { item in
                        conversationButton(item)
                            .listRowBackground(colors.backgroundPrimary)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                dmTrailingActions(item)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                dmLeadingActions(item)
                            }
                    }
                }
            }

            if !viewModel.tradeRoomItems.isEmpty {
                Section {
                    ForEach(viewModel.tradeRoomItems) { item in
                        Button {
                            viewModel.openRoom(item)
                        } label: {
                            TradeRoomInboxRowView(item: item, imagePipeline: imagePipeline)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(colors.backgroundSecondary)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task { await viewModel.leaveRoom(id: item.id) }
                            } label: {
                                Label("Leave Room", systemImage: "rectangle.portrait.and.arrow.right")
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
                    }
                } header: {
                    HStack(spacing: ExperienceSpacing.xs) {
                        ExperienceIcon(icon: .rooms, size: .sm, color: colors.accent)
                        Text("Trade Rooms")
                    }
                } footer: {
                    Text("Trade Rooms stay separate from your direct messages.")
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: viewModel.searchText)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: viewModel.directMessageItems.count)
    }

    private func conversationButton(_ item: DirectMessageInboxItem) -> some View {
        Button {
            viewModel.openConversation(item)
        } label: {
            ConversationRowView(item: item, imagePipeline: imagePipeline)
        }
        .buttonStyle(.plain)
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
    }
}
