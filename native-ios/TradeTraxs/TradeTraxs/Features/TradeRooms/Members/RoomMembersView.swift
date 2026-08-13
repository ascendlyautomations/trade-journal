import SwiftUI

struct RoomMembersView: View {
    @State private var viewModel: RoomMembersViewModel
    private let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors

    init(
        roomID: RoomID,
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator? = nil,
        navigationHost: TradeRoomNavigationHost = .messages
    ) {
        _viewModel = State(
            initialValue: RoomMembersViewModel(
                roomID: roomID,
                rooms: data.rooms,
                profiles: data.profiles,
                session: data.session,
                detailCache: data.detailCache,
                navigationCoordinator: navigationCoordinator,
                navigationHost: navigationHost
            )
        )
        self.imagePipeline = data.imagePipeline
    }

    init(viewModel: RoomMembersViewModel, imagePipeline: any ImagePipeline) {
        _viewModel = State(initialValue: viewModel)
        self.imagePipeline = imagePipeline
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle, .loading:
                ExperienceLoadingSpinner(label: "Loading members")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ExperienceErrorState(
                    title: "Couldn't load members",
                    message: message,
                    onRetry: { viewModel.retry() }
                )
            case .loaded where viewModel.members.isEmpty:
                ExperienceEmptyState(
                    icon: .rooms,
                    title: "No members yet",
                    message: "Members will appear as people join and chat."
                )
            case .loaded:
                List {
                    ForEach(viewModel.filteredMembers) { item in
                        RoomMemberRowView(item: item, imagePipeline: imagePipeline) {
                            viewModel.openProfile(item.id)
                        }
                        .listRowBackground(colors.backgroundPrimary)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Members")
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search members"
        )
        .task {
            viewModel.loadIfNeeded()
        }
        .accessibilityIdentifier("tradeRooms.members")
    }
}
