import PhotosUI
import SwiftUI

enum ManageRoomSection: Hashable {
    case details
    case channels
    case members
    case joinRequests
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
    @State private var cropSourceImage: UIImage?
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
            case .joinRequests: joinRequestsScreen
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
                hubRow("Edit Room Details", systemImage: "square.and.pencil") {
                    navigationSection = .details
                }
                hubRow("Channels", systemImage: "number") {
                    navigationSection = .channels
                }
                hubRow("Members", systemImage: "person.2") {
                    navigationSection = .members
                }
                if viewModel.showsJoinRequestsSection {
                    hubRow(
                        viewModel.pendingJoinRequestCount > 0
                            ? "Join Requests (\(viewModel.pendingJoinRequestCount))"
                            : "Join Requests",
                        systemImage: "person.badge.plus"
                    ) {
                        navigationSection = .joinRequests
                    }
                }
                hubRow("Tags", systemImage: "tag") {
                    navigationSection = .tags
                }
                hubRow("Banned Members", systemImage: "hand.raised") {
                    navigationSection = .banned
                }
                hubRow("Trade Room Settings", systemImage: "gearshape") {
                    viewModel.openRoomSettings()
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
            Section("Basic Info") {
                TextField("Room name", text: $viewModel.editConfiguration.name)
                TextField("Description", text: Binding(
                    get: { viewModel.editConfiguration.description ?? "" },
                    set: { viewModel.editConfiguration.description = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                .lineLimit(3...6)
                EditRoomDetailsImageSection(
                    pendingPreview: viewModel.pendingImagePreview,
                    savedReference: viewModel.savedImageReference,
                    marksForRemoval: viewModel.marksImageForRemoval,
                    imagePipeline: imagePipeline
                )
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(editRoomPhotoPickerLabel, systemImage: "photo")
                }
                if viewModel.hasDisplayImage {
                    Button("Remove Photo", role: .destructive) {
                        viewModel.clearPendingRoomImage()
                        photoItem = nil
                    }
                }
            }

            Section("Discovery") {
                Picker("Category", selection: Binding(
                    get: { viewModel.editConfiguration.category ?? .general },
                    set: { viewModel.editConfiguration.category = $0 }
                )) {
                    ForEach(TradeRoomCategory.allCases, id: \.self) { category in
                        Text(category.displayName).tag(category)
                    }
                }
                NavigationLink("Tags") {
                    manageTagsEditor
                }
            }

            Section("Access") {
                Picker("Room Visibility", selection: Binding(
                    get: { viewModel.editConfiguration.visibility },
                    set: { viewModel.editConfiguration.visibility = $0 }
                )) {
                    Text("Public").tag(TradeRoomVisibility.public)
                    Text("Private").tag(TradeRoomVisibility.private)
                }
                if viewModel.editConfiguration.visibility == .public {
                    Picker("Join Policy", selection: $viewModel.editConfiguration.joinPolicy) {
                        Text("Anyone can join").tag(TradeRoomJoinPolicy.open)
                        Text("Request to join").tag(TradeRoomJoinPolicy.approval)
                    }
                }
                Toggle("Show on my profile", isOn: $viewModel.editConfiguration.showsOnProfile)
            }

            Section("Room Rules") {
                TextField("Optional guidelines", text: Binding(
                    get: { viewModel.editConfiguration.rules ?? "" },
                    set: { viewModel.editConfiguration.rules = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                .lineLimit(4...8)
            }

            Section("Member Permissions") {
                Toggle("Members can send messages", isOn: $viewModel.editConfiguration.membersCanMessage)
                Toggle("Members can share trades", isOn: $viewModel.editConfiguration.membersCanShareTrades)
                Toggle("Members can share images/media", isOn: $viewModel.editConfiguration.membersCanShareMedia)
            }

        }
        .scrollContentBackground(.hidden)
        .experienceNavigationTitle("Edit Room Details")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { await viewModel.saveDetails() }
                }
                .fontWeight(.semibold)
                .disabled(viewModel.isSavingDetails)
                .accessibilityIdentifier("tradeRooms.manage.details.save")
            }
        }
        .disabled(viewModel.isSavingDetails)
        .experienceProtectedFormDismiss(viewModel.isSavingDetails)
        .onChange(of: photoItem) { _, item in
            Task { await presentRoomImageCrop(for: item) }
        }
        .imageCropSelection(
            sourceImage: $cropSourceImage,
            preset: .room,
            onConfirm: { result in
                viewModel.setCroppedRoomImage(result)
                cropSourceImage = nil
                photoItem = nil
            },
            onCancel: { photoItem = nil }
        )
    }

    private func presentRoomImageCrop(for item: PhotosPickerItem?) async {
        guard let image = await ImageCropSelectionSupport.loadUIImage(from: item) else { return }
        cropSourceImage = image
    }

    private var editRoomPhotoPickerLabel: String {
        viewModel.hasDisplayImage ? "Change Photo" : "Add Photo"
    }

    private var manageTagsEditor: some View {
        List {
            ForEach(TradeRoomConfigurationValidation.presetDiscoveryTags, id: \.self) { tag in
                Button {
                    toggleManageTag(tag)
                } label: {
                    HStack {
                        Text(tag)
                        Spacer()
                        if viewModel.editConfiguration.discoveryTags.contains(tag) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(colors.accent)
                        }
                    }
                }
            }
        }
        .experienceNavigationTitle("Tags")
    }

    private func toggleManageTag(_ tag: String) {
        if viewModel.editConfiguration.discoveryTags.contains(tag) {
            viewModel.editConfiguration.discoveryTags.removeAll { $0 == tag }
        } else if viewModel.editConfiguration.discoveryTags.count
            < TradeRoomConfigurationValidation.maxDiscoveryTags
        {
            viewModel.editConfiguration.discoveryTags.append(tag)
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

    private var joinRequestsScreen: some View {
        List {
            if viewModel.joinRequests.isEmpty {
                Text("No pending join requests.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            } else {
                ForEach(viewModel.joinRequests) { request in
                    HStack(spacing: ExperienceSpacing.sm) {
                        if let profile = request.profile {
                            FollowListAvatarView(profile: profile, imagePipeline: imagePipeline)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(request.profile?.displayName ?? "Trader")
                                .experienceStyle(.body, color: colors.primaryText)
                            if let username = request.profile?.username {
                                Text("@\(username)")
                                    .experienceStyle(.caption, color: colors.secondaryText)
                            }
                            if let createdAt = request.createdAt {
                                Text(createdAt.formatted(date: .abbreviated, time: .omitted))
                                    .experienceStyle(.caption2, color: colors.tertiaryText)
                            }
                        }
                        Spacer(minLength: 0)
                        HStack(spacing: ExperienceSpacing.xs) {
                            Button("Decline") {
                                Task { await viewModel.declineJoinRequest(request) }
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(colors.loss)
                            .disabled(viewModel.isMutatingJoinRequest)
                            Button("Approve") {
                                Task { await viewModel.approveJoinRequest(request) }
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(colors.accent)
                            .disabled(viewModel.isMutatingJoinRequest)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .experienceNavigationTitle("Join Requests")
        .refreshable { await viewModel.refreshJoinRequests() }
    }

    private var tagsScreen: some View {
        ManageRoomTagsView(
            viewModel: viewModel,
            newTagName: $newTagName,
            newTagColorKey: $newTagColorKey,
            editingTag: $editingTag
        )
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
        ManageRoomChannelsView(
            viewModel: viewModel,
            editingChannel: $editingChannel,
            showsCreateChannel: $showsCreateChannel
        )
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

/// Shows the authoritative saved room image, an in-progress crop preview, or the empty placeholder.
private struct EditRoomDetailsImageSection: View {
    let pendingPreview: UIImage?
    let savedReference: MediaReference?
    let marksForRemoval: Bool
    let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors
    @State private var savedPreview: UIImage?

    var body: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            Group {
                if let pendingPreview {
                    Image(uiImage: pendingPreview)
                        .resizable()
                        .scaledToFill()
                } else if marksForRemoval {
                    placeholder
                } else if let savedPreview {
                    Image(uiImage: savedPreview)
                        .resizable()
                        .scaledToFill()
                } else if savedReference != nil {
                    placeholder
                        .overlay {
                            ProgressView()
                        }
                } else {
                    placeholder
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Room Photo")
                    .experienceStyle(.subheadline, color: colors.primaryText)
                Text(savedReference != nil && !marksForRemoval && pendingPreview == nil
                    ? "Current room image"
                    : pendingPreview != nil
                        ? "New photo selected"
                        : "No room photo")
                    .experienceStyle(.caption, color: colors.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .task(id: savedReference?.id) {
            await loadSavedPreview()
        }
    }

    private var placeholder: some View {
        ZStack {
            colors.fillSecondary
            ExperienceIcon(icon: .rooms, size: .md, color: colors.accent)
        }
    }

    private func loadSavedPreview() async {
        guard !marksForRemoval, pendingPreview == nil else {
            savedPreview = nil
            return
        }
        guard let reference = savedReference else {
            savedPreview = nil
            return
        }
        do {
            let data = try await imagePipeline.data(
                for: ImageRequest(
                    reference: reference,
                    purpose: .profileAvatar,
                    maxPixelSize: 160
                )
            )
            if let ui = UIImage(data: data) {
                savedPreview = ui
            } else {
                savedPreview = nil
            }
        } catch {
            savedPreview = nil
        }
    }
}
