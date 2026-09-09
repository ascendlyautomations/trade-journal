import SwiftUI

struct RoomMembersView: View {
    @State private var viewModel: RoomMembersViewModel
    @State private var selectedMember: RoomMemberItem?
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
                            if viewModel.canManageRoom, viewModel.canManageMember(item) {
                                selectedMember = item
                            } else {
                                viewModel.openProfile(item.id)
                            }
                        }
                        .listRowBackground(colors.backgroundPrimary)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if viewModel.canManageMember(item) {
                                Button("Ban", role: .destructive) {
                                    viewModel.requestMemberAction(.ban(item.id))
                                }
                                Button("Remove", role: .destructive) {
                                    viewModel.requestMemberAction(.remove(item.id))
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Members")
        .toolbar {
            if viewModel.canManageRoom {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.openManageRoom()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(colors.primaryText)
                    }
                    .experienceTouchTarget()
                    .accessibilityLabel("Manage Room")
                    .accessibilityIdentifier("tradeRooms.members.manage")
                }
            }
        }
        .sheet(item: $selectedMember) { member in
            memberActionsSheet(member)
        }
        .confirmationDialog(
            memberActionDialogTitle,
            isPresented: $viewModel.showsMemberActionConfirmation,
            titleVisibility: .visible
        ) {
            if let action = viewModel.pendingMemberAction {
                Button(viewModel.memberActionButtonTitle(for: action), role: .destructive) {
                    Task { await viewModel.confirmMemberAction() }
                }
                Button("Cancel", role: .cancel) {
                    viewModel.pendingMemberAction = nil
                }
            }
        }
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search members"
        )
        .task(id: viewModel.roomID) {
            viewModel.loadIfNeeded()
        }
        .accessibilityIdentifier("tradeRooms.members")
    }

    @ViewBuilder
    private func memberActionsSheet(_ member: RoomMemberItem) -> some View {
        NavigationStack {
            List {
                Section {
                    RoomMemberRowView(item: member, imagePipeline: imagePipeline) {}
                        .disabled(true)
                }
                Section {
                    Button("View Profile") {
                        selectedMember = nil
                        viewModel.openProfile(member.id)
                    }
                    Button("Remove from Room", role: .destructive) {
                        selectedMember = nil
                        viewModel.requestMemberAction(.remove(member.id))
                    }
                    Button("Ban from Room", role: .destructive) {
                        selectedMember = nil
                        viewModel.requestMemberAction(.ban(member.id))
                    }
                }
            }
            .experienceNavigationTitle("Member")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { selectedMember = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var memberActionDialogTitle: String {
        guard let action = viewModel.pendingMemberAction else { return "" }
        return viewModel.memberActionTitle(for: action)
    }
}
