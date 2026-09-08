import PhotosUI
import SwiftUI

enum ManageRoomSection: Hashable {
    case details
    case channels
    case members
    case tags
    case banned
}

struct ManageRoomView: View {
    @State private var viewModel: ManageRoomViewModel
    private let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors
    @State private var navigationSection: ManageRoomSection?
    @State private var selectedMember: RoomManagedMember?
    @State private var photoItem: PhotosPickerItem?
    @State private var editingTag: RoomMemberTag?
    @State private var editingChannel: RoomChannel?
    @State private var showsCreateChannel = false
    @State private var newTagName = ""
    @State private var newTagColorKey = RoomMemberTagSupport.defaultColorKey

    init(
        roomID: RoomID,
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator? = nil,
        navigationHost: TradeRoomNavigationHost = .messages
    ) {
        precondition(
            data.rooms is any RoomManagementRepository,
            "Manage Room requires RoomManagementRepository"
        )
        _viewModel = State(
            initialValue: ManageRoomViewModel(
                roomID: roomID,
                rooms: data.rooms as! any RoomManagementRepository,
                uploadService: data.uploadService,
                session: data.session,
                detailCache: data.detailCache,
                navigationCoordinator: navigationCoordinator,
                navigationHost: navigationHost
            )
        )
        self.imagePipeline = data.imagePipeline
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle, .loading:
                ExperienceLoadingSpinner(label: "Loading manage room")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ExperienceErrorState(
                    title: "Couldn't open Manage Room",
                    message: message,
                    onRetry: { viewModel.retry() }
                )
            case .loaded:
                hub
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Manage Room")
        .task { viewModel.loadIfNeeded() }
        .navigationDestination(item: $navigationSection) { section in
            switch section {
            case .details: detailsScreen
            case .channels: channelsScreen
            case .members: membersScreen
            case .tags: tagsScreen
            case .banned: bannedScreen
            }
        }
        .confirmationDialog(
            channelDeleteTitle,
            isPresented: Binding(
                get: { viewModel.pendingChannelDelete != nil },
                set: { if !$0 { viewModel.pendingChannelDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pending = viewModel.pendingChannelDelete {
                Button("Delete Channel", role: .destructive) {
                    Task { await viewModel.confirmDeleteChannel(pending.channelID) }
                }
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingChannelDelete = nil
            }
        } message: {
            Text(channelDeleteMessage)
        }
        .confirmationDialog(
            memberActionTitle,
            isPresented: Binding(
                get: { viewModel.pendingMemberAction != nil },
                set: { if !$0 { viewModel.pendingMemberAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let action = viewModel.pendingMemberAction {
                Button(actionButtonTitle(action), role: .destructive) {
                    Task { await viewModel.confirmMemberAction(action) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $selectedMember) { member in
            memberActionsSheet(member)
        }
        .sheet(item: $editingTag) { tag in
            tagEditorSheet(tag)
        }
        .sheet(isPresented: $showsCreateChannel) {
            channelEditorSheet(channel: nil)
        }
        .sheet(item: $editingChannel) { channel in
            channelEditorSheet(channel: channel)
        }
        .accessibilityIdentifier("tradeRooms.manage")
    }

    private var hub: some View {
        List {
            Section {
                hubRow("Room Details", systemImage: "square.and.pencil") {
                    navigationSection = .details
                }
                hubRow("Channels", systemImage: "number") {
                    navigationSection = .channels
                }
                hubRow("Members", systemImage: "person.2") {
                    navigationSection = .members
                }
                hubRow("Tags", systemImage: "tag") {
                    navigationSection = .tags
                }
                hubRow("Banned Members", systemImage: "hand.raised") {
                    navigationSection = .banned
                }
            }
            if let statusMessage = viewModel.statusMessage {
                Section {
                    Text(statusMessage)
                        .experienceStyle(.footnote, color: colors.secondaryText)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var detailsScreen: some View {
        Form {
            Section("Room Name") {
                TextField("Room name", text: $viewModel.editName)
            }
            Section("Description") {
                TextField("Description", text: $viewModel.editDescription, axis: .vertical)
                    .lineLimit(3...6)
            }
            Section("Picture") {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Choose New Picture", systemImage: "photo")
                }
            }
            Section("Privacy") {
                Toggle("Show on my profile", isOn: $viewModel.editShowsOnProfile)
            }
            Section {
                Button {
                    Task { await viewModel.saveDetails() }
                } label: {
                    if viewModel.isSavingDetails {
                        ProgressView()
                    } else {
                        Text("Save Changes")
                    }
                }
                .disabled(viewModel.isSavingDetails)
            }
        }
        .scrollContentBackground(.hidden)
        .experienceNavigationTitle("Room Details")
        .experienceProtectedFormDismiss(viewModel.isSavingDetails)
        .task(id: photoItem?.itemIdentifier) {
            guard let photoItem else { return }
            if let data = try? await photoItem.loadTransferable(type: Data.self) {
                viewModel.pendingImageData = data
            }
        }
    }

    private var membersScreen: some View {
        List {
            ForEach(viewModel.members) { member in
                Button {
                    selectedMember = member
                } label: {
                    managedMemberRow(member)
                }
                .disabled(member.role == .owner)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .experienceNavigationTitle("Members")
        .refreshable { await viewModel.refreshMembersAndBans() }
    }

    private var tagsScreen: some View {
        List {
            Section("Create Tag") {
                TextField("Tag name", text: $newTagName)
                Picker("Color", selection: $newTagColorKey) {
                    ForEach(RoomMemberTagSupport.presetColorKeys, id: \.key) { option in
                        Text(option.label).tag(option.key)
                    }
                }
                Button("Create Tag") {
                    Task {
                        await viewModel.createTag(name: newTagName, colorKey: newTagColorKey)
                        newTagName = ""
                    }
                }
                .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isMutatingTag)
            }
            Section("Tags") {
                ForEach(viewModel.tags) { tag in
                    Button {
                        editingTag = tag
                    } label: {
                        HStack {
                            Circle()
                                .fill(RoomMemberTagSupport.color(for: tag.colorKey, colors: colors))
                                .frame(width: 10, height: 10)
                            Text(tag.name)
                                .experienceStyle(.body, color: colors.primaryText)
                            if tag.isPreset {
                                Text("Preset")
                                    .experienceStyle(.caption2, color: colors.tertiaryText)
                            }
                            Spacer()
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let tag = viewModel.tags[index]
                        Task { await viewModel.deleteTag(tag) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .experienceNavigationTitle("Tags")
        .refreshable { await viewModel.refreshTags() }
    }

    private var bannedScreen: some View {
        List {
            if viewModel.bans.isEmpty {
                Text("No banned members")
                    .experienceStyle(.body, color: colors.tertiaryText)
            } else {
                ForEach(viewModel.bans) { ban in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ban.profile.displayName)
                                .experienceStyle(.subheadline, color: colors.primaryText)
                            Text("@\(ban.profile.username)")
                                .experienceStyle(.caption, color: colors.secondaryText)
                        }
                        Spacer()
                        Button("Unban") {
                            Task { await viewModel.unban(ban) }
                        }
                        .disabled(viewModel.isMutatingMember)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .experienceNavigationTitle("Banned Members")
        .refreshable { await viewModel.refreshMembersAndBans() }
    }

    @ViewBuilder
    private func memberActionsSheet(_ member: RoomManagedMember) -> some View {
        NavigationStack {
            List {
                Section {
                    managedMemberRow(member)
                }
                Section {
                    Button("View Profile") {
                        selectedMember = nil
                        viewModel.openProfile(member.profile.id)
                    }
                    NavigationLink("Manage Tags") {
                        memberTagsEditor(member)
                    }
                    Button("Remove from Room", role: .destructive) {
                        selectedMember = nil
                        viewModel.pendingMemberAction = .remove(member.profile.id)
                    }
                    Button("Ban from Room", role: .destructive) {
                        selectedMember = nil
                        viewModel.pendingMemberAction = .ban(member.profile.id)
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

    private func memberTagsEditor(_ member: RoomManagedMember) -> some View {
        List {
            ForEach(viewModel.tags) { tag in
                let assigned = member.tags.contains(where: { $0.id == tag.id })
                Button {
                    Task { await viewModel.toggleTag(tag, for: member) }
                } label: {
                    HStack {
                        Text(tag.name)
                            .experienceStyle(.body, color: colors.primaryText)
                        Spacer()
                        if assigned {
                            Image(systemName: "checkmark")
                                .foregroundStyle(colors.accent)
                        }
                    }
                }
                .disabled(viewModel.isMutatingTag)
            }
        }
        .experienceNavigationTitle("Manage Tags")
    }

    @ViewBuilder
    private func tagEditorSheet(_ tag: RoomMemberTag) -> some View {
        NavigationStack {
            Form {
                TextField("Name", text: Binding(
                    get: { editingTag?.name ?? tag.name },
                    set: { editingTag?.name = $0 }
                ))
                Picker("Color", selection: Binding(
                    get: { editingTag?.colorKey ?? tag.colorKey },
                    set: { editingTag?.colorKey = $0 }
                )) {
                    ForEach(RoomMemberTagSupport.presetColorKeys, id: \.key) { option in
                        Text(option.label).tag(option.key)
                    }
                }
            }
            .experienceNavigationTitle("Edit Tag")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editingTag = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let editingTag else { return }
                        Task {
                            await viewModel.updateTag(editingTag)
                            self.editingTag = nil
                        }
                    }
                }
            }
            .onAppear { editingTag = tag }
        }
        .presentationDetents([.medium])
        .experienceProtectedFormDismiss()
    }

    private var channelsScreen: some View {
        List {
            Section {
                ForEach(Array(viewModel.channels.sorted { $0.position < $1.position }.enumerated()), id: \.element.id) { index, channel in
                    HStack {
                        Button {
                            editingChannel = channel
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(channel.displayTitle)
                                    .experienceStyle(.body, color: colors.primaryText)
                                Text(channel.allowMembersChat ? "Members can chat" : "Owner announcements only")
                                    .experienceStyle(.caption, color: colors.secondaryText)
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        if index > 0 {
                            Button {
                                Task { await viewModel.moveChannel(channel, direction: -1) }
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .disabled(viewModel.isMutatingChannel)
                        }
                        if index < viewModel.channels.count - 1 {
                            Button {
                                Task { await viewModel.moveChannel(channel, direction: 1) }
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .disabled(viewModel.isMutatingChannel)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { await viewModel.requestDeleteChannel(channel) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(viewModel.channels.count <= RoomChannelValidation.minCount)
                    }
                }
            }
            if viewModel.channels.count < RoomChannelValidation.maxCount {
                Section {
                    Button {
                        showsCreateChannel = true
                    } label: {
                        Label("Create Channel", systemImage: "plus")
                    }
                    .disabled(viewModel.isMutatingChannel)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .experienceNavigationTitle("Channels")
        .refreshable { await viewModel.refreshChannels() }
    }

    @ViewBuilder
    private func channelEditorSheet(channel: RoomChannel?) -> some View {
        ManageRoomChannelEditorSheet(
            channel: channel,
            isSaving: viewModel.isMutatingChannel,
            onCancel: {
                if channel == nil {
                    showsCreateChannel = false
                } else {
                    editingChannel = nil
                }
            },
            onSave: { name, allowChat in
                Task {
                    let success: Bool
                    if let channel {
                        success = await viewModel.updateChannel(channel, name: name, allowMembersChat: allowChat)
                        if success { editingChannel = nil }
                    } else {
                        success = await viewModel.createChannel(name: name, allowMembersChat: allowChat)
                        if success { showsCreateChannel = false }
                    }
                }
            }
        )
    }

    private var channelDeleteTitle: String {
        "Delete this channel?"
    }

    private var channelDeleteMessage: String {
        guard let pending = viewModel.pendingChannelDelete else { return "" }
        switch pending {
        case .empty:
            return "This channel has no messages."
        case .withMessages(_, let count):
            return "This will permanently delete \(count) message\(count == 1 ? "" : "s") in this channel."
        }
    }

    private func managedMemberRow(_ member: RoomManagedMember) -> some View {
        HStack(spacing: ExperienceSpacing.md) {
            FollowListAvatarView(profile: member.profile, imagePipeline: imagePipeline)
            VStack(alignment: .leading, spacing: 4) {
                Text(member.profile.displayName)
                    .experienceStyle(.subheadline, color: colors.primaryText)
                Text("@\(member.profile.username)")
                    .experienceStyle(.caption, color: colors.secondaryText)
                RoomMemberTagChipsView(
                    tags: member.tags,
                    showsOwnerBadge: member.role == .owner
                )
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, ExperienceSpacing.xxs)
    }

    private func hubRow(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(colors.accent)
                Text(title)
                    .experienceStyle(.body, color: colors.primaryText)
                Spacer()
                ExperienceIcon(icon: .forward, size: .sm, color: colors.tertiaryText)
            }
        }
    }

    private var memberActionTitle: String {
        switch viewModel.pendingMemberAction {
        case .remove: return "Remove this member from the room?"
        case .ban: return "Ban this member from the room?"
        case nil: return ""
        }
    }

    private func actionButtonTitle(_ action: ManageRoomViewModel.MemberAction) -> String {
        switch action {
        case .remove: return "Remove Member"
        case .ban: return "Ban Member"
        }
    }
}
