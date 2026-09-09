import PhotosUI
import SwiftUI

/// Native Create Trade Room — full setup flow via authoritative `rpc_v1_create_trade_room`.
struct CreateRoomView: View {
    @State private var viewModel: CreateRoomViewModel
    @State private var photoItem: PhotosPickerItem?
    @State private var showsDiscardConfirm = false
    @State private var cropSourceImage: UIImage?
    @State private var showsCategoryPicker = false
    @State private var showsTagsPicker = false

    @Environment(\.themeColors) private var colors
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name
        case description
        case rules
        case subRoom(UUID)
    }

    init(
        data: DataEnvironment,
        onDismiss: @escaping () -> Void,
        onCreated: @escaping (TradeRoom) -> Void
    ) {
        _viewModel = State(
            initialValue: CreateRoomViewModel(
                rooms: data.rooms,
                profiles: data.profiles,
                uploadService: data.uploadService,
                session: data.session,
                detailCache: data.detailCache,
                onDismiss: onDismiss,
                onCreated: onCreated
            )
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .idle, .loading:
                    ExperienceLoadingSpinner(label: "Loading")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    ExperienceErrorState(
                        title: "Couldn't open Create Room",
                        message: message,
                        onRetry: { viewModel.retryLoad() }
                    )
                case .ready, .creating:
                    formContent
                }
            }
            .experienceScreenBackground()
            .experienceNavigationTitle("Create Trade Room")
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if viewModel.phase == .ready || viewModel.phase == .creating {
                    createBar
                }
            }
            .confirmationDialog(
                "Discard this room?",
                isPresented: $showsDiscardConfirm,
                titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive) { viewModel.dismissRequested() }
                Button("Keep Editing", role: .cancel) {}
            }
            .experienceProtectedFormDismiss()
            .task { viewModel.loadIfNeeded() }
            .onChange(of: photoItem) { _, item in
                Task { await presentRoomImageCrop(for: item) }
            }
            .imageCropSelection(
                sourceImage: $cropSourceImage,
                preset: .room,
                onConfirm: { result in
                    viewModel.setCroppedImage(result)
                    cropSourceImage = nil
                    photoItem = nil
                },
                onCancel: { photoItem = nil }
            )
            .sheet(isPresented: $showsCategoryPicker) {
                categoryPickerSheet
            }
            .sheet(isPresented: $showsTagsPicker) {
                tagsPickerSheet
            }
        }
        .accessibilityIdentifier("createRoom.root")
    }

    @ViewBuilder
    private var formContent: some View {
        if viewModel.existingOwnedRoom != nil {
            ExperienceEmptyState(
                icon: .rooms,
                title: "You already have a Trade Room",
                message: "Each trader can own one Trade Room. Open yours to manage it or invite members.",
                actionTitle: "Open My Trade Room",
                action: { viewModel.openExistingOwnedRoom() }
            )
            .padding(.horizontal, ExperienceSpacing.md)
        } else {
            Form {
                basicInfoSection
                discoverySection
                accessSection
                subRoomsSection
                rulesSection
                permissionsSection

                if let formError = viewModel.formError {
                    Section {
                        Text(formError)
                            .experienceStyle(.footnote, color: colors.loss)
                            .accessibilityIdentifier("createRoom.formError")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .disabled(viewModel.isSubmitting)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var basicInfoSection: some View {
        Section {
            TextField("Room name", text: $viewModel.configuration.name)
                .focused($focusedField, equals: .name)
                .textInputAutocapitalization(.words)
                .accessibilityIdentifier("createRoom.name")

            TextField("Optional description", text: Binding(
                get: { viewModel.configuration.description ?? "" },
                set: { viewModel.configuration.description = $0.isEmpty ? nil : $0 }
            ), axis: .vertical)
            .focused($focusedField, equals: .description)
            .lineLimit(3...6)
            .accessibilityIdentifier("createRoom.description")

            if let preview = viewModel.imagePreview {
                HStack(spacing: ExperienceSpacing.sm) {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())
                    Button("Remove Picture", role: .destructive) {
                        viewModel.clearImage()
                        photoItem = nil
                    }
                }
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(roomPhotoPickerLabel, systemImage: "photo")
            }
            .disabled(viewModel.isSubmitting)
            .accessibilityIdentifier("createRoom.imagePicker")
        } header: {
            Text("Basic Info")
        } footer: {
            Text("Room name is required.")
        }
    }

    private var roomPhotoPickerLabel: String {
        viewModel.imagePreview == nil ? "Choose Picture" : "Replace Picture"
    }

    private var discoverySection: some View {
        Section {
            Button {
                showsCategoryPicker = true
            } label: {
                HStack {
                    Text("Category")
                        .foregroundStyle(colors.primaryText)
                    Spacer()
                    Text(viewModel.configuration.category?.displayName ?? "General")
                        .foregroundStyle(colors.secondaryText)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(colors.tertiaryText)
                }
            }
            .accessibilityIdentifier("createRoom.category")

            Button {
                showsTagsPicker = true
            } label: {
                HStack {
                    Text("Tags")
                        .foregroundStyle(colors.primaryText)
                    Spacer()
                    Text(tagsSummary)
                        .foregroundStyle(colors.secondaryText)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(colors.tertiaryText)
                }
            }
            .accessibilityIdentifier("createRoom.tags")
        } header: {
            Text("Discovery")
        } footer: {
            Text("Tags help traders find your room in Explore. Choose up to \(TradeRoomConfigurationValidation.maxDiscoveryTags).")
        }
    }

    private var accessSection: some View {
        Section {
            Picker("Room Visibility", selection: Binding(
                get: { viewModel.configuration.visibility },
                set: { viewModel.setVisibility($0) }
            )) {
                ForEach([TradeRoomVisibility.public, .private], id: \.self) { visibility in
                    Text(visibility.displayName).tag(visibility)
                }
            }
            .accessibilityIdentifier("createRoom.visibility")

            if viewModel.showsJoinPolicy {
                Picker("Join Policy", selection: $viewModel.configuration.joinPolicy) {
                    ForEach([TradeRoomJoinPolicy.open, .approval], id: \.self) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }
                .accessibilityIdentifier("createRoom.joinPolicy")
            }

            Toggle("Show on my profile", isOn: $viewModel.configuration.showsOnProfile)
                .accessibilityIdentifier("createRoom.showOnProfile")
        } header: {
            Text("Access")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.configuration.visibility.summary)
                Text("Profile visibility is separate — hiding from your profile does not make the room private.")
            }
        }
    }

    private var subRoomsSection: some View {
        Section {
            ForEach($viewModel.configuration.channels) { $channel in
                HStack(spacing: ExperienceSpacing.sm) {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(colors.tertiaryText)
                    TextField("Sub-room name", text: $channel.name)
                        .focused($focusedField, equals: .subRoom(channel.id))
                        .textInputAutocapitalization(.words)
                }
            }
            .onMove(perform: viewModel.moveSubRooms)
            .onDelete { offsets in
                for index in offsets {
                    let id = viewModel.configuration.channels[index].id
                    viewModel.removeSubRoom(id: id)
                }
            }

            if viewModel.configuration.channels.count < TradeRoomConfigurationValidation.maxChannels {
                Button {
                    viewModel.addSubRoom()
                } label: {
                    Label("Add Sub-Room", systemImage: "plus")
                }
                .accessibilityIdentifier("createRoom.addSubRoom")
            }
        } header: {
            Text("Sub-Rooms")
        } footer: {
            Text("Configure channels before creating. You can edit them later in Manage Room.")
        }
    }

    private var rulesSection: some View {
        Section {
            TextField(
                "Optional guidelines for members",
                text: Binding(
                    get: { viewModel.configuration.rules ?? "" },
                    set: { viewModel.configuration.rules = $0.isEmpty ? nil : $0 }
                ),
                axis: .vertical
            )
            .focused($focusedField, equals: .rules)
            .lineLimit(4...8)
            .accessibilityIdentifier("createRoom.rules")
        } header: {
            Text("Room Rules")
        }
    }

    private var permissionsSection: some View {
        Section {
            Toggle("Members can send messages", isOn: $viewModel.configuration.membersCanMessage)
            Toggle("Members can share trades", isOn: $viewModel.configuration.membersCanShareTrades)
            Toggle("Members can share images/media", isOn: $viewModel.configuration.membersCanShareMedia)
        } header: {
            Text("Member Permissions")
        } footer: {
            Text("These settings are enforced by the messaging system.")
        }
    }

    private var categoryPickerSheet: some View {
        NavigationStack {
            List {
                ForEach(TradeRoomCategory.allCases, id: \.self) { category in
                    Button {
                        viewModel.configuration.category = category
                        showsCategoryPicker = false
                    } label: {
                        HStack {
                            Text(category.displayName)
                                .foregroundStyle(colors.primaryText)
                            Spacer()
                            if viewModel.configuration.category == category {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(colors.accent)
                            }
                        }
                    }
                }
            }
            .experienceNavigationTitle("Category")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showsCategoryPicker = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var tagsPickerSheet: some View {
        NavigationStack {
            List {
                ForEach(TradeRoomConfigurationValidation.presetDiscoveryTags, id: \.self) { tag in
                    Button {
                        viewModel.toggleDiscoveryTag(tag)
                    } label: {
                        HStack {
                            Text(tag)
                                .foregroundStyle(colors.primaryText)
                            Spacer()
                            if viewModel.configuration.discoveryTags.contains(tag) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(colors.accent)
                            }
                        }
                    }
                    .disabled(
                        !viewModel.configuration.discoveryTags.contains(tag)
                            && viewModel.configuration.discoveryTags.count
                                >= TradeRoomConfigurationValidation.maxDiscoveryTags
                    )
                }
            }
            .experienceNavigationTitle("Tags")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showsTagsPicker = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var tagsSummary: String {
        let tags = viewModel.configuration.discoveryTags
        if tags.isEmpty { return "None" }
        return tags.joined(separator: ", ")
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { requestDismiss() }
                .font(.body.weight(.regular))
                .disabled(viewModel.isSubmitting)
        }
        if viewModel.existingOwnedRoom == nil {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
                    .disabled(viewModel.isSubmitting)
            }
        }
    }

    private var createBar: some View {
        CreateComposerPublishBar(
            title: "Create Trade Room",
            loadingTitle: viewModel.isUploadingImage ? "Uploading…" : "Creating…",
            isEnabled: viewModel.canCreate,
            isLoading: viewModel.isSubmitting,
            accessibilityIdentifier: "createRoom.submit"
        ) {
            focusedField = nil
            viewModel.create()
        }
    }

    private func requestDismiss() {
        if viewModel.hasUnsavedChanges && viewModel.existingOwnedRoom == nil {
            showsDiscardConfirm = true
        } else {
            viewModel.dismissRequested()
        }
    }

    private func presentRoomImageCrop(for item: PhotosPickerItem?) async {
        guard let image = await ImageCropSelectionSupport.loadUIImage(from: item) else { return }
        cropSourceImage = image
    }
}
