import PhotosUI
import SwiftUI

struct ProfileOnboardingView: View {
    @State private var viewModel: ProfileOnboardingViewModel
    @State private var photoItem: PhotosPickerItem?
    @State private var cropSourceImage: UIImage?
    @State private var photoPickerLoadID = UUID()
    @FocusState private var usernameFieldFocused: Bool
    @Environment(\.themeColors) private var colors
    let imagePipeline: any ImagePipeline
    let onSignOut: () -> Void

    init(
        viewModel: ProfileOnboardingViewModel,
        imagePipeline: any ImagePipeline,
        onSignOut: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: viewModel)
        self.imagePipeline = imagePipeline
        self.onSignOut = onSignOut
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                    brandingHeader
                    pageHeader
                    profileSection
                    tradingProfileSection

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .experienceStyle(.footnote, color: colors.error)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ExperienceButton(
                        title: viewModel.isSubmitting ? "Saving…" : "Finish setup",
                        kind: .primary,
                        isEnabled: viewModel.canSubmit,
                        keepsEnabledAppearanceWhenDisabled: true,
                        isLoading: viewModel.isSubmitting,
                        accessibilityIdentifier: "onboarding.submit"
                    ) {
                        Task { await viewModel.submit() }
                    }
                    .padding(.top, ExperienceSpacing.xs)

                    if viewModel.canContinueWithoutPhoto {
                        Button {
                            Task { await viewModel.continueWithoutPhoto() }
                        } label: {
                            Text("Continue without photo")
                                .experienceStyle(.body, color: colors.accent)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isSubmitting)
                        .accessibilityIdentifier("onboarding.continueWithoutPhoto")
                    }

                    Button(action: onSignOut) {
                        Text("Use a different account")
                            .experienceStyle(.footnote, color: colors.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("onboarding.signOut")
                }
                .experiencePadding(.lg)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height, alignment: .top)
                .padding(.top, ExperienceSpacing.sm)
            }
            .experienceFormScrollKeyboard()
        }
        .experienceScreenBackground()
        .experienceKeyboardDismissOnTapOutside()
        .experienceProtectedFormDismiss()
        .experienceFormKeyboard(isFocused: $usernameFieldFocused)
        .onChange(of: viewModel.usernameError) { _, error in
            if error != nil {
                usernameFieldFocused = true
            }
        }
        .onChange(of: photoItem) { _, item in
#if DEBUG
            ProfilePhotoDebugLog.selectionChanged(hasItem: item != nil)
#endif
            guard item != nil else { return }
            let loadID = UUID()
            photoPickerLoadID = loadID
            Task { await presentAvatarCrop(for: item, loadID: loadID) }
        }
        .imageCropSelectionBaked(
            sourceImage: $cropSourceImage,
            preset: .avatar,
            onConfirm: { image in
                viewModel.setAvatarImage(image)
                photoItem = nil
            },
            onCancel: { photoItem = nil }
        )
    }

    // MARK: - Header

    private var brandingHeader: some View {
        VStack(spacing: ExperienceSpacing.xs) {
            Image("AppLogo")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)

            Text("TradeTraxs")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(colors.primaryText)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            HStack(alignment: .firstTextBaseline) {
                Text("Let's Get Your Account Ready")
                    .font(ExperienceTypography.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(colors.primaryText)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: ExperienceSpacing.sm)

                Text("Step 1 of 2")
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                    .accessibilityLabel("Profile setup, step 1 of 2")
            }

            Text("Set up your trading profile so TradeTraxs can personalize your experience.")
                .experienceStyle(.footnote, color: colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

        }
    }

    // MARK: - Profile

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            onboardingSectionLabel("Profile")

            ProfileOnboardingGroupedSurface {
                compactAvatarRow
                ExperienceDivider()
                nameRow
                ExperienceDivider()
                usernameRow
                ExperienceDivider()
                bioRow
            }
        }
    }

    private var compactAvatarRow: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            HStack(spacing: ExperienceSpacing.sm) {
                avatarThumbnail
                    .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                    let avatarButtonTitle = viewModel.avatarPreview == nil
                        ? "Add profile photo"
                        : "Change photo"
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Text(avatarButtonTitle)
                            .experienceStyle(.body, color: colors.accent)
                    }
                    .accessibilityIdentifier("onboarding.avatarPicker")

                    Text("Optional")
                        .experienceStyle(.caption2, color: colors.tertiaryText)

                    if viewModel.avatarPreview != nil || viewModel.prefilledAvatarReference != nil {
                        Button {
                            photoItem = nil
                            viewModel.clearAvatarSelection()
                        } label: {
                            Text("Remove")
                                .experienceStyle(.caption, color: colors.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer(minLength: 0)
            }

            if let avatarUploadError = viewModel.avatarUploadError {
                Text(avatarUploadError)
                    .experienceStyle(.caption, color: colors.error)
            }
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
            } else if let reference = viewModel.prefilledAvatarReference {
                TradeImageView(
                    reference: reference,
                    imagePipeline: imagePipeline,
                    purpose: .profileAvatar,
                    contentMode: .fill,
                    side: 52
                )
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(colors.secondaryText.opacity(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clipShape(Circle())
        .overlay(Circle().stroke(colors.border, lineWidth: ExperienceBorder.hairline))
    }

    private var nameRow: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            Text("Name")
                .experienceStyle(.caption, color: colors.secondaryText)

            TextField("Your name", text: $viewModel.displayName)
                .textInputAutocapitalization(.words)
                .textContentType(.name)
                .autocorrectionDisabled()
                .padding(.vertical, ExperienceSpacing.xxs)

            if let displayNameError = viewModel.displayNameError {
                Text(displayNameError)
                    .experienceStyle(.caption, color: colors.error)
            }
        }
        .padding(.vertical, ExperienceSpacing.xxs)
        .accessibilityIdentifier("onboarding.displayName")
    }

    private var usernameRow: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            Text("Username")
                .experienceStyle(.caption, color: colors.secondaryText)

            HStack(spacing: ExperienceSpacing.xxs) {
                Text("@")
                    .experienceStyle(.body, color: colors.secondaryText)
                    .accessibilityHidden(true)

                TextField("username", text: $viewModel.username)
                    .focused($usernameFieldFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .textContentType(.username)
                    .onChange(of: viewModel.username) { _, newValue in
                        let sanitized = ProfileUsernamePolicy.sanitizeForTyping(newValue)
                        if sanitized != newValue {
                            viewModel.username = sanitized
                        }
                        viewModel.clearUsernameError()
                    }
            }
                    .padding(.vertical, ExperienceSpacing.xxs)

            usernameFeedbackArea
        }
        .padding(.vertical, ExperienceSpacing.xxs)
    }

    private var usernameFeedbackArea: some View {
        Group {
            if let usernameError = viewModel.usernameError {
                Text(usernameError)
                    .experienceStyle(.caption, color: colors.error)
            } else {
                Text(ProfileUsernamePolicy.formatHint)
                    .experienceStyle(.caption2, color: colors.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .topLeading)
    }

    private var bioRow: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            Text("Bio")
                .experienceStyle(.caption, color: colors.secondaryText)

            TextField("Optional — tell traders about yourself", text: $viewModel.bio, axis: .vertical)
                .lineLimit(2...4)
                .textInputAutocapitalization(.sentences)
                    .padding(.vertical, ExperienceSpacing.xxs)
                .frame(minHeight: 44, maxHeight: 88, alignment: .topLeading)
        }
        .padding(.vertical, ExperienceSpacing.xxs)
    }

    // MARK: - Trading profile

    private var tradingProfileSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            onboardingSectionLabel("Trading Profile")

            ProfileOnboardingGroupedSurface {
                traderTypeRow
                ExperienceDivider()
                tradingStyleRow
                ExperienceDivider()
                startedTradingRow
            }
        }
    }

    private var traderTypeRow: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text("Trader Type")
                .experienceStyle(.caption, color: colors.secondaryText)

            HStack(spacing: ExperienceSpacing.xs) {
                ForEach([TraderType.futures, .options, .investor], id: \.self) { type in
                    ExperienceChip(
                        title: type.rawValue,
                        isSelected: viewModel.traderType == type
                    ) {
                        viewModel.traderType = type
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, ExperienceSpacing.xxs)
        .accessibilityElement(children: .contain)
    }

    private var tradingStyleRow: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            Text("Trading Style")
                .experienceStyle(.caption, color: colors.secondaryText)

            TextField("e.g. Scalping, swing, investor…", text: $viewModel.tradingStyle)
                .textInputAutocapitalization(.words)
                    .padding(.vertical, ExperienceSpacing.xxs)
        }
        .padding(.vertical, ExperienceSpacing.xxs)
    }

    private var startedTradingRow: some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
            Text("Started Trading")
                .experienceStyle(.body, color: colors.primaryText)

            Spacer(minLength: ExperienceSpacing.sm)

            DatePicker(
                "Started trading",
                selection: startedTradingBinding,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .tint(colors.accent)
        }
        .padding(.vertical, ExperienceSpacing.xxs)
        .frame(minHeight: ExperienceAccessibility.minTouchTarget)
    }

    private func onboardingSectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(.caption2, design: .default).weight(.semibold))
            .foregroundStyle(colors.secondaryText)
            .textCase(.uppercase)
            .tracking(0.35)
            .accessibilityAddTraits(.isHeader)
    }

    private var startedTradingBinding: Binding<Date> {
        Binding(
            get: {
                let formatter = DateFormatter()
                formatter.calendar = Calendar.current
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "yyyy-MM-dd"
                return formatter.date(from: viewModel.startedTrading) ?? Date()
            },
            set: { newDate in
                let formatter = DateFormatter()
                formatter.calendar = Calendar.current
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "yyyy-MM-dd"
                viewModel.startedTrading = formatter.string(from: newDate)
            }
        )
    }

    private func presentAvatarCrop(for item: PhotosPickerItem?, loadID: UUID) async {
        guard let item else { return }
        guard loadID == photoPickerLoadID else { return }

        switch await ImageCropSelectionSupport.loadUIImageOutcome(from: item) {
        case .success(let image):
            guard loadID == photoPickerLoadID, !Task.isCancelled else { return }
            viewModel.avatarUploadError = nil
#if DEBUG
            ProfilePhotoDebugLog.cropperPresented()
#endif
            cropSourceImage = image
        case .cancelled:
            return
        case .failed:
            guard loadID == photoPickerLoadID, !Task.isCancelled else { return }
            viewModel.avatarUploadError = "Couldn't load that photo. Try another image."
        }
    }
}

// MARK: - Grouped surface

private struct ProfileOnboardingGroupedSurface<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.vertical, ExperienceSpacing.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            colors.surfacePrimary,
            in: RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                .stroke(colors.border.opacity(ExperienceOpacity.subtle), lineWidth: ExperienceBorder.hairline)
        }
    }
}
