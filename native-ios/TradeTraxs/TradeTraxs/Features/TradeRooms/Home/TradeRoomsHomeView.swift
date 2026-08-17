import SwiftUI

/// Dedicated Trade Rooms home — member rooms with search, refresh, and empty/error states.
struct TradeRoomsHomeView: View {
    @State private var viewModel: TradeRoomsHomeViewModel
    private let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator,
        navigationHost: TradeRoomNavigationHost = .messages
    ) {
        _viewModel = State(
            initialValue: TradeRoomsHomeViewModel(
                messages: data.messages,
                rooms: data.rooms,
                profiles: data.profiles,
                session: data.session,
                detailCache: data.detailCache,
                navigationCoordinator: navigationCoordinator,
                navigationHost: navigationHost,
                realtimeHub: data.realtimeHub
            )
        )
        self.imagePipeline = data.imagePipeline
    }

    /// Tests / previews.
    init(viewModel: TradeRoomsHomeViewModel, imagePipeline: any ImagePipeline) {
        _viewModel = State(initialValue: viewModel)
        self.imagePipeline = imagePipeline
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle, .loading:
                if !viewModel.items.isEmpty {
                    roomList
                } else {
                    TradeRoomsSkeleton()
                }
            case .failed(let message):
                if !viewModel.items.isEmpty {
                    roomList
                } else {
                    ExperienceErrorState(
                        title: "Couldn't load Trade Rooms",
                        message: message,
                        onRetry: { Task { await viewModel.refresh() } }
                    )
                }
            case .loaded where viewModel.showsEmpty:
                ExperienceEmptyState(
                    icon: .rooms,
                    title: "No Trade Rooms yet",
                    message: "Join a community room to trade ideas with other traders."
                )
            case .loaded:
                roomList
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Trade Rooms")
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search rooms"
        )
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            viewModel.loadIfNeeded()
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

    /// Force Observation of shared room unread so badges clear without leave/refresh.
    private var roomUnreadObservation: [RoomID: Int] {
        MessagesInboxStore.shared.roomUnread
    }

    private var roomList: some View {
        let _ = roomUnreadObservation
        return ScrollView {
            LazyVStack(spacing: ExperienceSpacing.md) {
                if viewModel.showsFilteredEmpty {
                    ExperienceEmptyState(
                        icon: .search,
                        title: "No matches",
                        message: "Try a different room name or owner."
                    )
                    .padding(.top, ExperienceSpacing.xl)
                }

                ForEach(viewModel.filteredItems) { item in
                    Button {
                        viewModel.openRoom(item)
                    } label: {
                        TradeRoomCardView(item: item, imagePipeline: imagePipeline)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
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
                                systemImage: item.isMuted ? "bell.fill" : "bell.slash.fill"
                            )
                        }
                        Divider()
                        Button(role: .destructive) {
                            viewModel.requestLeaveRoom(id: item.id)
                        } label: {
                            Label("Leave Room", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } preview: {
                        TradeRoomCardView(item: item, imagePipeline: imagePipeline)
                            .frame(width: 320)
                            .padding()
                    }
                }
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.vertical, ExperienceSpacing.sm)
            .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: viewModel.searchText)
        }
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("tradeRooms.list")
    }
}
