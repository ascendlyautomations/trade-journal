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
                if let username = viewModel.profile?.username {
                    SettingsInfoRow(title: "Username", value: "@\(username)")
                }
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
                Text("This is how other traders see you on TradeTraxs.")
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
}
