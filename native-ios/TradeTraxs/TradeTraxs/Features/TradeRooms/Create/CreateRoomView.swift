import PhotosUI
import SwiftUI

/// Native Create Trade Room — web `createUserRoom` parity with setup fields upfront.
struct CreateRoomView: View {
    @State private var viewModel: CreateRoomViewModel
    @State private var photoItem: PhotosPickerItem?
    @State private var showsDiscardConfirm = false
    @State private var cropSourceImage: UIImage?

    private let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name
        case description
    }

    init(
        data: DataEnvironment,
        onDismiss: @escaping () -> Void,
        onCreated: @escaping (TradeRoom) -> Void
    ) {
        imagePipeline = data.imagePipeline
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
            .imageCropSelectionBaked(
                sourceImage: $cropSourceImage,
                preset: .room,
                onConfirm: { viewModel.setImage($0) },
                onCancel: { photoItem = nil }
            )
        }
        .accessibilityIdentifier("createRoom.root")
    }

    @ViewBuilder
    private var formContent: some View {
        if let existing = viewModel.existingOwnedRoom {
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
                Section("Room Name") {
                    TextField("Room name", text: $viewModel.name)
                        .focused($focusedField, equals: .name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("createRoom.name")
                }

                Section("Description") {
                    TextField("Optional description", text: $viewModel.descriptionText, axis: .vertical)
                        .focused($focusedField, equals: .description)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("createRoom.description")
                }

                Section("Picture") {
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
                        Label(
                            viewModel.imagePreview == nil ? "Choose Picture" : "Replace Picture",
                            systemImage: "photo"
                        )
                    }
                    .disabled(viewModel.isSubmitting)
                    .accessibilityIdentifier("createRoom.imagePicker")
                }

                Section("Privacy") {
                    Toggle("Show on my profile", isOn: $viewModel.showsOnProfile)
                        .accessibilityIdentifier("createRoom.showOnProfile")
                    Text("When off, your room is invite-link only and hidden from public discovery.")
                        .font(.footnote)
                        .foregroundStyle(colors.secondaryText)
                }

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

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { requestDismiss() }
                .font(.body.weight(.regular))
                .disabled(viewModel.isSubmitting)
        }
    }

    private var createBar: some View {
        CreateComposerPublishBar(
            title: "Create",
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
