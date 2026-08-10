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

            Section("Public Identity") {
                if let username = viewModel.profile?.username {
                    SettingsInfoRow(title: "Username", value: "@\(username)")
                }
                TextField("Display name", text: $viewModel.draftDisplayName)
                TextField("Bio", text: $viewModel.draftBio, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section("Trading") {
                TextField("Trading style", text: $viewModel.draftTradingStyle)
                TextField("Primary market", text: $viewModel.draftPrimaryMarket)
                if let traderType = viewModel.profile?.traderType {
                    SettingsInfoRow(title: "Trader type", value: traderType.rawValue)
                }
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

            Section {
                Button("Save Changes") {
                    viewModel.save()
                }
                .disabled(viewModel.profile == nil)
            }
        }
        .scrollContentBackground(.hidden)
        .background(colors.groupedBackground.ignoresSafeArea())
        .navigationTitle("Profile")
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .onAppear { viewModel.loadIfNeeded() }
        .accessibilityIdentifier("settings.profile")
    }
}
