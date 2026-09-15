import SwiftUI

struct SharedContentShareRecipientPickerView: View {
    let scope: SharedContentShareViewModel.RecipientScope
    @Bindable var viewModel: SharedContentShareViewModel
    let imagePipeline: any ImagePipeline
    var onSendSuccess: () -> Void
    var onClose: () -> Void

    @State private var searchText = ""
    @FocusState private var messageFieldFocused: Bool

    @Environment(\.themeColors) private var colors

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .idle, .loading:
                    ExperienceLoadingSpinner(label: loadingLabel)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    ExperienceErrorState(
                        title: "Couldn't load recipients",
                        message: message,
                        onRetry: { Task { await viewModel.loadRecipients(for: scope) } }
                    )
                case .loaded, .sending, .sent:
                    recipientList
                }
            }
            .experienceScreenBackground()
            .navigationTitle(scope == .messages ? "Messages" : "Trade Rooms")
            .navigationBarTitleDisplayMode(.inline)
            .experienceArrowBackToolbarButton(action: onClose)
            .searchable(text: $searchText, prompt: searchPrompt)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if viewModel.hasSelection {
                    shareComposerBar
                }
            }
            .task(id: scope) {
                await viewModel.loadRecipients(for: scope)
            }
            .alert(
                "Couldn't send",
                isPresented: Binding(
                    get: { viewModel.sendErrorMessage != nil },
                    set: { if !$0 { viewModel.clearSendError() } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.sendErrorMessage ?? "")
            }
        }
        .experienceSheetChrome()
    }

    @ViewBuilder
    private var recipientList: some View {
        let empty = scope == .messages ? filteredConversations.isEmpty : filteredRooms.isEmpty
        if empty {
            ExperienceEmptyState(
                icon: scope == .messages ? .messages : .rooms,
                title: emptyTitle,
                message: emptyMessage
            )
        } else {
            List {
                switch scope {
                case .messages:
                    ForEach(filteredConversations) { conversation in
                        Button {
                            viewModel.toggleConversationSelection(conversation)
                        } label: {
                            ShareRecipientConversationRow(
                                conversation: conversation,
                                imagePipeline: imagePipeline,
                                isSelected: viewModel.isConversationSelected(conversation.id)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.phase == .sending)
                        .accessibilityIdentifier("sharedContentShare.conversation.\(conversation.id.rawValue)")
                    }
                case .rooms:
                    ForEach(filteredRooms) { room in
                        Button {
                            viewModel.toggleRoomSelection(room)
                        } label: {
                            ShareRecipientTradeRoomRow(
                                room: room,
                                imagePipeline: imagePipeline,
                                isSelected: viewModel.isRoomSelected(room.id)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.phase == .sending)
                        .accessibilityIdentifier("sharedContentShare.room.\(room.id.rawValue)")
                    }
                }
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var shareComposerBar: some View {
        VStack(spacing: ExperienceSpacing.sm) {
            TextField("Add a message...", text: $viewModel.accompanyingMessage, axis: .vertical)
                .lineLimit(1 ... 4)
                .textFieldStyle(.plain)
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.vertical, ExperienceSpacing.sm)
                .background(colors.fillSecondary, in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
                .focused($messageFieldFocused)
                .disabled(viewModel.phase == .sending)
                .submitLabel(.done)
                .onSubmit {
                    messageFieldFocused = false
                }
                .accessibilityIdentifier("sharedContentShare.messageField")

            ExperienceButton(
                title: sendButtonTitle,
                kind: .primary,
                isEnabled: viewModel.hasSelection,
                isLoading: viewModel.phase == .sending,
                accessibilityIdentifier: "sharedContentShare.send"
            ) {
                messageFieldFocused = false
                Task {
                    if await viewModel.sendToSelected() {
                        onSendSuccess()
                    }
                }
            }
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.top, ExperienceSpacing.sm)
        .padding(.bottom, ExperienceSpacing.md)
        .background {
            Rectangle()
                .fill(.bar)
                .overlay(alignment: .top) {
                    Divider()
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var sendButtonTitle: String {
        let count = viewModel.selectedDestinationCount
        if count <= 1 {
            return "Send"
        }
        return "Send to \(count)"
    }

    private var filteredConversations: [Conversation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return viewModel.conversations }
        return viewModel.conversations.filter { conversation in
            let title = conversation.title?.lowercased() ?? ""
            let username = conversation.peerUsername?.lowercased() ?? ""
            return title.contains(query) || username.contains(query)
        }
    }

    private var filteredRooms: [TradeRoom] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return viewModel.rooms }
        return viewModel.rooms.filter { room in
            room.name.lowercased().contains(query)
                || (room.description?.lowercased().contains(query) ?? false)
        }
    }

    private var loadingLabel: String {
        scope == .messages ? "Loading conversations" : "Loading Trade Rooms"
    }

    private var searchPrompt: String {
        scope == .messages ? "Search conversations" : "Search Trade Rooms"
    }

    private var emptyTitle: String {
        scope == .messages ? "No conversations" : "No Trade Rooms"
    }

    private var emptyMessage: String {
        scope == .messages
            ? "Start a conversation to share this content."
            : "Join a Trade Room to share this content."
    }
}
