import PhotosUI
import SwiftUI

struct SettingsProfileView: View {
    @State private var viewModel: SettingsProfileViewModel
    @State private var photoItem: PhotosPickerItem?
    @State private var cropSourceImage: UIImage?
    @State private var photoPickerLoadID = UUID()

    @Environment(\.themeColors) private var colors
    @Environment(\.appEnvironment) private var appEnvironment

    private let imagePipeline: any ImagePipeline

    init(
        data: DataEnvironment,
        profileStore: CurrentUserProfileStore?,
        appConfiguration: AppConfiguration
    ) {
        imagePipeline = data.imagePipeline
        _viewModel = State(
            initialValue: SettingsProfileViewModel(
                profiles: data.profiles,
                session: data.session,
                profileStore: profileStore,
                uploadService: data.uploadService,
                objectStorage: data.objectStorage,
                supabaseURL: appConfiguration.supabaseURL
            )
        )
    }

    init(viewModel: SettingsProfileViewModel, imagePipeline: any ImagePipeline) {
        self.imagePipeline = imagePipeline
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Form {
            if let error = viewModel.errorMessage {
                Section {
                    SettingsInlineError(message: error) {
                        Task { await viewModel.refresh() }
                    }
                }
            }

            Section {
                profilePhotoRow
            }

            Section {
                usernameField
                SettingsLabeledField(title: "Display Name") {
                    TextField("Your name", text: $viewModel.draftDisplayName)
                        .textInputAutocapitalization(.words)
                }
                SettingsLabeledField(title: "Bio") {
                    TextField("Tell traders about yourself", text: $viewModel.draftBio, axis: .vertical)
                        .lineLimit(3...6)
                }
            }

            Section {
                traderTypeRow
            }

            Section {
                SettingsLabeledField(title: "Trading Style") {
                    TextField("e.g. Scalper, Swing", text: $viewModel.draftTradingStyle)
                        .textInputAutocapitalization(.words)
                }
                SettingsLabeledField(title: "Primary Market") {
                    TextField("e.g. Futures, Options", text: $viewModel.draftPrimaryMarket)
                        .textInputAutocapitalization(.words)
                }
            } header: {
                Text("Trading")
            }

            Section {
                SettingsToggleRow(
                    title: "Private profile",
                    subtitle: "Follow requests required to see your content",
                    isOn: Binding(
                        get: { viewModel.draftIsPrivate },
                        set: { viewModel.setPrivate($0) }
                    )
                )
            } header: {
                Text("Privacy")
            }

            if let saveMessage = viewModel.saveMessage {
                Section {
                    Text(saveMessage)
                        .experienceStyle(.footnote, color: colors.success)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .experienceDashboardGroupedRows()
        .scrollDismissesKeyboard(.interactively)
        .background(colors.groupedBackground.ignoresSafeArea())
        .experienceNavigationTitle("Profile")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    viewModel.save()
                }
                .fontWeight(.semibold)
                .disabled(viewModel.profile == nil)
                .accessibilityIdentifier("settings.profile.save")
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .onAppear {
            viewModel.loadIfNeeded()
        }
        .onChange(of: photoItem) { _, item in
            guard item != nil else { return }
            let loadID = UUID()
            photoPickerLoadID = loadID
            Task { await presentAvatarCrop(for: item, loadID: loadID) }
        }
        .imageCropSelectionBaked(
            sourceImage: $cropSourceImage,
            preset: .avatar,
            onConfirm: { image in
                viewModel.persistCroppedAvatar(image)
                photoItem = nil
            },
            onCancel: { photoItem = nil }
        )
        .accessibilityIdentifier("settings.profile")
    }

    private var profilePhotoRow: some View {
        HStack(spacing: ExperienceSpacing.md) {
            avatarThumbnail
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                if viewModel.canChangeAvatar {
                    PhotosPicker(
                        selection: $photoItem,
                        matching: ProfilePhotoPickerFilter.matching,
                        preferredItemEncoding: .compatible
                    ) {
                        Text("Change Photo")
                            .experienceStyle(.body, color: colors.accent)
                    }
                    .disabled(viewModel.isUploadingAvatar)
                    .accessibilityIdentifier("settings.profile.avatarPicker")
                }

                if viewModel.isUploadingAvatar {
                    ProgressView()
                        .controlSize(.small)
                }

                if let avatarUploadError = viewModel.avatarUploadError {
                    Text(avatarUploadError)
                        .experienceStyle(.caption, color: colors.error)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, ExperienceSpacing.xxs)
    }

    @ViewBuilder
    private var avatarThumbnail: some View {
        Group {
            if let preview = viewModel.avatarPreview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFill()
            } else if let reference = viewModel.profile?.avatar {
                TradeImageView(
                    reference: reference,
                    imagePipeline: imagePipeline,
                    purpose: .profileAvatar,
                    contentMode: .fill,
                    side: 64
                )
            } else if let uiImage = appEnvironment.currentUserProfile.avatarUIImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(colors.secondaryText.opacity(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clipShape(Circle())
        .overlay(Circle().stroke(colors.border, lineWidth: ExperienceBorder.hairline))
    }

    private var traderTypeRow: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Trader Type")
                .experienceStyle(.caption, color: colors.secondaryText)

            HStack(spacing: ExperienceSpacing.xs) {
                ForEach([TraderType.futures, .options, .investor], id: \.self) { type in
                    ExperienceChip(
                        title: type.rawValue,
                        isSelected: viewModel.draftTraderType == type
                    ) {
                        viewModel.setTraderType(type)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, ExperienceSpacing.xxs)
        .accessibilityIdentifier("settings.profile.traderType")
    }

    private var usernameField: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            Text("Username")
                .experienceStyle(.caption, color: colors.secondaryText)

            HStack(spacing: ExperienceSpacing.xxs) {
                Text("@")
                    .experienceStyle(.body, color: colors.secondaryText)
                    .accessibilityHidden(true)

                TextField("username", text: $viewModel.draftUsername)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .textContentType(.username)
                    .disabled(viewModel.atUsernameChangeLimit)
                    .onChange(of: viewModel.draftUsername) { _, newValue in
                        let sanitized = ProfileUsernamePolicy.sanitizeForTyping(newValue)
                        if sanitized != newValue {
                            viewModel.draftUsername = sanitized
                        }
                        viewModel.clearUsernameError()
                    }
            }
            .padding(.vertical, ExperienceSpacing.xxs)

            if let usernameError = viewModel.usernameError {
                Text(usernameError)
                    .experienceStyle(.caption, color: colors.error)
            } else {
                Text(ProfileUsernamePolicy.formatHint)
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                Text("Remaining changes: \(viewModel.remainingUsernameChanges)")
                    .experienceStyle(.caption2, color: colors.tertiaryText)
            }
        }
        .padding(.vertical, ExperienceSpacing.xxs)
        .accessibilityIdentifier("settings.profile.username")
    }

    private func presentAvatarCrop(for item: PhotosPickerItem?, loadID: UUID) async {
        guard let item else { return }
        guard loadID == photoPickerLoadID else { return }

        switch await ImageCropSelectionSupport.loadProfileAvatarUIImageOutcome(from: item) {
        case .success(let image):
            guard loadID == photoPickerLoadID, !Task.isCancelled else { return }
            viewModel.clearAvatarUploadError()
            cropSourceImage = image
        case .cancelled:
            return
        case .failed:
            guard loadID == photoPickerLoadID, !Task.isCancelled else { return }
            viewModel.noteAvatarPhotoLoadFailed()
        }
    }
}
