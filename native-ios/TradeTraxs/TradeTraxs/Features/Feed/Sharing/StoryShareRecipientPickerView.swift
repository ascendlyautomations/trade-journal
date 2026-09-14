import SwiftUI

struct StoryShareRecipientPickerView: View {
    let scope: StoryShareViewModel.RecipientScope
    @Bindable var viewModel: StoryShareViewModel
    let imagePipeline: any ImagePipeline
    var onSelectConversation: (Conversation) -> Void
    var onSelectRoom: (TradeRoom) -> Void
    var onClose: () -> Void

    @State private var searchText = ""

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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back", action: onClose)
                }
            }
            .searchable(text: $searchText, prompt: searchPrompt)
            .task(id: scope) {
                await viewModel.loadRecipients(for: scope)
            }
            .alert(
                "Couldn't send story",
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
                            Task {
                                if await viewModel.send(to: conversation) {
                                    onSelectConversation(conversation)
                                }
                            }
                        } label: {
                            ShareRecipientConversationRow(
                                conversation: conversation,
                                imagePipeline: imagePipeline
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.phase == .sending)
                    }
                case .rooms:
                    ForEach(filteredRooms) { room in
                        Button {
                            Task {
                                if await viewModel.send(to: room) {
                                    onSelectRoom(room)
                                }
                            }
                        } label: {
                            ShareRecipientTradeRoomRow(room: room, imagePipeline: imagePipeline)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.phase == .sending)
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if viewModel.phase == .sending {
                    ProgressView("Sending…")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
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
            ? "Start a conversation to share this story."
            : "Join a Trade Room to share this story."
    }
}
