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
    private let avatarSize: CGFloat = 52

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
        List {
            if let error = viewModel.errorMessage {
                Section {
                    SettingsInlineError(message: error) {
                        Task { await viewModel.refresh() }
                    }
                }
            }

            Section {
                identitySection
                SettingsLabeledField(title: "Display Name") {
                    TextField("Your name", text: $viewModel.draftDisplayName)
                        .textInputAutocapitalization(.words)
                }
                SettingsLabeledField(title: "Bio") {
                    ProfileBioTextField(
                        text: $viewModel.draftBio,
                        placeholder: "Tell traders about yourself",
                        maxHeight: 88
                    )
                }
            } header: {
                Text("Profile")
            }

            Section {
                traderTypeRow
                SettingsLabeledField(title: ProfileTradingStyleField.label) {
                    TextField(ProfileTradingStyleField.placeholder, text: $viewModel.draftTradingStyle)
                        .textInputAutocapitalization(.words)
                }
                .accessibilityIdentifier("settings.profile.tradingStyle")
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

        }
        .experienceInsetGroupedListStyle(pageBackground: true)
        .listSectionSpacing(ExperienceSpacing.xxs)
        .contentMargins(.top, ExperienceSpacing.xxs, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
        .experienceNavigationTitle("Profile")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    viewModel.save()
                }
                .fontWeight(.semibold)
                .disabled(viewModel.profile == nil || viewModel.isSaving)
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

    private var identitySection: some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
            avatarThumbnail
                .frame(width: avatarSize, height: avatarSize)

            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                usernameEditor

                if viewModel.canChangeAvatar {
                    PhotosPicker(
                        selection: $photoItem,
                        matching: MediaPickerPolicy.profilePhoto.matching,
                        preferredItemEncoding: .compatible
                    ) {
                        Text("Change Photo")
                            .experienceStyle(.footnote, color: colors.accent)
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
        }
        .accessibilityElement(children: .contain)
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
                    side: avatarSize
                )
            } else if let uiImage = appEnvironment.currentUserProfile.avatarUIImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: avatarSize * 0.85))
                    .foregroundStyle(colors.secondaryText.opacity(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clipShape(Circle())
        .overlay(Circle().stroke(colors.border, lineWidth: ExperienceBorder.hairline))
    }

    private var traderTypeRow: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            Text("Trader Type")
                .experienceStyle(.footnote, color: colors.secondaryText)

            HStack(spacing: ExperienceSpacing.xxs) {
                ForEach(TraderType.profileSelectableCases, id: \.self) { type in
                    ExperienceChip(
                        title: type.rawValue,
                        isSelected: viewModel.draftTraderType == type,
                        compact: true
                    ) {
                        viewModel.setTraderType(type)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("settings.profile.traderType")
    }

    private var usernameEditor: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Username")
                .experienceStyle(.footnote, color: colors.secondaryText)

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

            if let usernameError = viewModel.usernameError {
                Text(usernameError)
                    .experienceStyle(.caption, color: colors.error)
            } else {
                Text(ProfileUsernamePolicy.formatHint)
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                Text("Remaining username changes: \(viewModel.remainingUsernameChanges)")
                    .experienceStyle(.caption2, color: colors.tertiaryText)
            }
        }
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
