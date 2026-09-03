import PhotosUI
import SwiftUI

struct ProfileOnboardingView: View {
    @State private var viewModel: ProfileOnboardingViewModel
    @State private var photoItem: PhotosPickerItem?
    @FocusState private var usernameFieldFocused: Bool
    @Environment(\.themeColors) private var colors

    init(viewModel: ProfileOnboardingViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                header
                avatarPicker
                usernameField
                tradingStyleField
                traderTypeField
                startedTradingField
                bioField
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .experienceStyle(.footnote, color: colors.error)
                }
                ExperienceButton(
                    title: viewModel.isSubmitting ? "Saving…" : "Finish setup",
                    kind: .primary,
                    isEnabled: viewModel.canSubmit,
                    isLoading: viewModel.isSubmitting,
                    accessibilityIdentifier: "onboarding.submit"
                ) {
                    Task { await viewModel.submit() }
                }
            }
            .experiencePadding(.xl)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .experienceScreenBackground()
        .interactiveDismissDisabled(true)
        .onChange(of: viewModel.usernameError) { _, error in
            if error != nil {
                usernameFieldFocused = true
            }
        }
        .onChange(of: photoItem) { _, item in
            Task { await loadPhoto(item) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Let's get your account ready")
                .experienceStyle(.title2, color: colors.primaryText)
            Text("Choose a username and a few trading details to unlock TradeTraxs.")
                .experienceStyle(.body, color: colors.secondaryText)
            if !viewModel.displayName.isEmpty {
                Text("Signed in as \(viewModel.displayName)")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }
        }
        .padding(.top, ExperienceSpacing.xxl)
    }

    private var avatarPicker: some View {
        VStack(spacing: ExperienceSpacing.sm) {
            Group {
                if let preview = viewModel.avatarPreview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(colors.secondaryText.opacity(0.55))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(Circle())
            .overlay(Circle().stroke(colors.secondaryText.opacity(0.25), lineWidth: 1))

            PhotosPicker(selection: $photoItem, matching: .images) {
                Text(viewModel.avatarPreview == nil ? "Add Profile Picture" : "Change Profile Picture")
                    .experienceStyle(.footnote, color: colors.primaryText)
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.vertical, ExperienceSpacing.sm)
                    .background(colors.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous))
            }

            if viewModel.avatarPreview != nil {
                Button {
                    photoItem = nil
                    viewModel.clearAvatarSelection()
                } label: {
                    Text("Remove photo")
                        .experienceStyle(.caption, color: colors.secondaryText)
                }
            }

            Text("Optional")
                .experienceStyle(.caption, color: colors.secondaryText)

            if let avatarUploadError = viewModel.avatarUploadError {
                Text(avatarUploadError)
                    .experienceStyle(.caption, color: colors.error)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, ExperienceSpacing.sm)
    }

    private var usernameField: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text("Username")
                .experienceStyle(.footnote, color: colors.secondaryText)
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
                .padding(ExperienceSpacing.md)
                .background(colors.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous))
            if let usernameError = viewModel.usernameError {
                Text(usernameError)
                    .experienceStyle(.caption, color: colors.error)
            }
            Text(ProfileUsernamePolicy.formatHint)
                .experienceStyle(.caption, color: colors.secondaryText)
        }
    }

    private var tradingStyleField: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text("Trading style")
                .experienceStyle(.footnote, color: colors.secondaryText)
            TextField("e.g. Scalping, swing, investor…", text: $viewModel.tradingStyle)
                .padding(ExperienceSpacing.md)
                .background(colors.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous))
        }
    }

    private var traderTypeField: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text("Trader type")
                .experienceStyle(.footnote, color: colors.secondaryText)
            Picker("Trader type", selection: $viewModel.traderType) {
                Text("Select trader type").tag(Optional<TraderType>.none)
                ForEach([TraderType.futures, .options, .investor], id: \.self) { type in
                    Text(type.rawValue).tag(Optional(type))
                }
            }
            .pickerStyle(.menu)
            .padding(ExperienceSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous))
        }
    }

    private var startedTradingField: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text("Started trading")
                .experienceStyle(.footnote, color: colors.secondaryText)
            DatePicker(
                "Started trading",
                selection: startedTradingBinding,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .padding(ExperienceSpacing.md)
            .background(colors.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous))
        }
    }

    private var bioField: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text("Bio (optional)")
                .experienceStyle(.footnote, color: colors.secondaryText)
            TextField("Short bio", text: $viewModel.bio, axis: .vertical)
                .lineLimit(3...5)
                .padding(ExperienceSpacing.md)
                .background(colors.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous))
        }
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

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else {
                viewModel.avatarUploadError = "Couldn't load that photo. Try another image."
                return
            }
            viewModel.setAvatarImage(image)
        } catch {
            viewModel.avatarUploadError = "Couldn't load that photo. Try another image."
        }
    }
}
