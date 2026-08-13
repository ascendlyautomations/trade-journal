import SwiftUI

struct SettingsPrivacyView: View {
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
        List {
            if let error = viewModel.errorMessage {
                Section {
                    SettingsInlineError(message: error) {
                        Task { await viewModel.refresh() }
                    }
                }
            }

            Section {
                SettingsToggleRow(
                    title: "Private profile",
                    subtitle: "Only approved followers can see your profile content",
                    isOn: Binding(
                        get: { viewModel.draftIsPrivate },
                        set: { viewModel.setPrivate($0) }
                    )
                )
            } footer: {
                Text("When private, others must request to follow you before seeing your content.")
            }

            Section("Coming Later") {
                SettingsInfoRow(title: "Blocked accounts", value: "Prepared")
                SettingsInfoRow(title: "Muted accounts", value: "Prepared")
                SettingsInfoRow(title: "Who can message me", value: "Prepared")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(colors.groupedBackground.ignoresSafeArea())
        .experienceNavigationTitle("Privacy")
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .onAppear { viewModel.loadIfNeeded() }
        .accessibilityIdentifier("settings.privacy")
    }
}
