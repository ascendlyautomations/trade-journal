import SwiftUI

struct SettingsProfileView: View {
    @State private var viewModel: SettingsProfileViewModel

    @Environment(\.themeColors) private var colors

    init(data: DataEnvironment, profileStore: CurrentUserProfileStore?) {
        _viewModel = State(
            initialValue: SettingsProfileViewModel(
                profiles: data.profiles,
                session: data.session,
                profileStore: profileStore
            )
        )
    }

    init(viewModel: SettingsProfileViewModel) {
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
                usernameField
                SettingsLabeledField(title: "Display Name") {
                    TextField("Your name", text: $viewModel.draftDisplayName)
                        .textInputAutocapitalization(.words)
                }
                SettingsLabeledField(title: "Bio") {
                    TextField("Tell traders about yourself", text: $viewModel.draftBio, axis: .vertical)
                        .lineLimit(3...6)
                }
            } header: {
                Text("Public Identity")
            } footer: {
                VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                    Text("This is how other traders see you on TradeTraxs.")
                    Text("You may change your username up to 2 times.")
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                    if viewModel.atUsernameChangeLimit {
                        Text("Maximum username changes reached.")
                            .experienceStyle(.caption2, color: colors.warning)
                    } else {
                        Text("Remaining changes: \(viewModel.remainingUsernameChanges)")
                            .experienceStyle(.caption2, color: colors.tertiaryText)
                    }
                }
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
                if let traderType = viewModel.profile?.traderType {
                    SettingsInfoRow(title: "Trader Type", value: traderType.rawValue)
                }
            } header: {
                Text("Trading")
            } footer: {
                Text("Optional details shown on your public profile.")
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
            } footer: {
                Text("Control what other traders can see.")
            }

            if let saveMessage = viewModel.saveMessage {
                Section {
                    Text(saveMessage)
                        .experienceStyle(.footnote, color: colors.success)
                }
            }
        }
        .scrollContentBackground(.hidden)
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
        .onAppear { viewModel.loadIfNeeded() }
        .accessibilityIdentifier("settings.profile")
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
            }
        }
        .padding(.vertical, ExperienceSpacing.xxs)
        .accessibilityIdentifier("settings.profile.username")
    }
}
