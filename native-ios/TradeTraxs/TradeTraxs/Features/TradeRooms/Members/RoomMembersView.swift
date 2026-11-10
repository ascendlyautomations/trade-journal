import SwiftUI

struct RoomMembersView: View {
    @State private var viewModel: RoomMembersViewModel
    @State private var selectedMember: RoomMemberItem?
    @State private var memberForTags: RoomMemberItem?
    @State private var memberTagDraftSelection: Set<RoomMemberTagID> = []
    private let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors
    @Bindable private var roomMemberTagStore = SessionRoomMemberTagsStore.shared

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
                        RoomMemberRowView(
                            item: item,
                            imagePipeline: imagePipeline,
                            showsManageButton: viewModel.canShowManageMember(item),
                            onManage: { selectedMember = item },
                            onOpen: {
                                if viewModel.canShowManageMember(item) {
                                    selectedMember = item
                                } else {
                                    viewModel.openProfile(item.id)
                                }
                            }
                        )
                        .experienceDashboardListRow()
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if viewModel.canBanMember(item) {
                                Button("Ban Member", role: .destructive) {
                                    viewModel.requestMemberAction(.ban(item.id))
                                }
                            }
                            if viewModel.canRemoveMember(item) {
                                Button("Remove", role: .destructive) {
                                    viewModel.requestMemberAction(.remove(item.id))
                                }
                            }
                        }
                    }
                }
                .experienceInsetGroupedListStyle(pageBackground: true)
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
                            .experienceTouchTarget()
                    }
                    .accessibilityLabel("Manage Room")
                    .accessibilityIdentifier("tradeRooms.members.manage")
                }
            }
        }
        .sheet(item: $selectedMember) { member in
            memberManagementSheet(member)
        }
        .sheet(item: $memberForTags) { member in
            NavigationStack {
                memberTagsEditor(member)
                    .experienceNavigationTitle("Manage Tags")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                memberForTags = nil
                            }
                            .disabled(viewModel.isMutatingTag)
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                Task {
                                    let saved = await viewModel.saveMemberTagAssignments(
                                        for: member,
                                        selectedTagIDs: memberTagDraftSelection
                                    )
                                    if saved {
                                        memberForTags = nil
                                    }
                                }
                            }
                            .fontWeight(.semibold)
                            .disabled(viewModel.isMutatingTag)
                        }
                    }
            }
            .experienceScreenBackground()
            .presentationBackground(colors.sheetBackground)
            .onAppear {
                memberTagDraftSelection = viewModel.savedTagIDs(for: member.id)
            }
            .onChange(of: member.id) { _, _ in
                memberTagDraftSelection = viewModel.savedTagIDs(for: member.id)
            }
        }
        .roomMemberModerationConfirmations(
            showsRemoveConfirmation: $viewModel.showsMemberActionConfirmation,
            showsBanConfirmation: $viewModel.showsBanMemberConfirmation,
            removeDialogTitle: memberActionDialogTitle,
            onConfirmRemove: { Task { await viewModel.confirmMemberAction() } },
            onConfirmBan: { Task { await viewModel.confirmMemberAction() } },
            onCancelRemove: { viewModel.pendingMemberAction = nil },
            onCancelBan: { viewModel.cancelBanMember() }
        )
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search members"
        )
        .task(id: viewModel.roomID) {
            viewModel.loadIfNeeded()
        }
        .onChange(of: roomMemberTagStore.revision) { _, _ in
            viewModel.syncMemberTagsFromStore()
        }
        .accessibilityIdentifier("tradeRooms.members")
    }

    @ViewBuilder
    private func memberManagementSheet(_ member: RoomMemberItem) -> some View {
        RoomMemberManagementSheet(
            member: member,
            imagePipeline: imagePipeline,
            canRemove: viewModel.canRemoveMember(member),
            canBan: viewModel.canBanMember(member),
            onViewProfile: {
                selectedMember = nil
                viewModel.openProfile(member.id)
            },
            onRemove: {
                selectedMember = nil
                viewModel.requestMemberAction(.remove(member.id))
            },
            onBan: {
                selectedMember = nil
                viewModel.requestMemberAction(.ban(member.id))
            },
            onDismiss: { selectedMember = nil },
            onManageTags: viewModel.canManageTagsForMember(member)
                ? {
                    let item = member
                    selectedMember = nil
                    memberForTags = item
                }
                : nil
        )
    }

    private func memberTagsEditor(_ member: RoomMemberItem) -> some View {
        RoomMemberTagAssignmentEditor(
            tags: viewModel.roomTags.filter { viewModel.canAssignTag($0) },
            selectedTagIDs: $memberTagDraftSelection,
            isSaving: viewModel.isMutatingTag
        )
        .task { await viewModel.refreshTags() }
    }

    private var memberActionDialogTitle: String {
        guard let action = viewModel.pendingMemberAction else { return "" }
        return viewModel.memberActionTitle(for: action)
    }
}
