import SwiftUI

struct SettingsPrivacyView: View {
    @State private var profilePrivacy: SettingsProfileViewModel
    @State private var viewModel: SettingsPrivacyViewModel

    @Environment(\.stackNavigation) private var stackNavigation
    @Environment(\.themeColors) private var colors

    init(data: DataEnvironment, profileStore: CurrentUserProfileStore?) {
        let profileVM = SettingsProfileViewModel(
            profiles: data.profiles,
            session: data.session,
            profileStore: profileStore
        )
        _profilePrivacy = State(initialValue: profileVM)
        _viewModel = State(
            initialValue: SettingsPrivacyViewModel(
                profiles: data.profiles,
                messages: data.messages,
                session: data.session,
                profilePrivacy: profileVM
            )
        )
    }

    init(viewModel: SettingsPrivacyViewModel, profilePrivacy: SettingsProfileViewModel) {
        _profilePrivacy = State(initialValue: profilePrivacy)
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        List {
            if let error = viewModel.errorMessage ?? viewModel.profileErrorMessage {
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
                        set: { viewModel.draftIsPrivate = $0 }
                    )
                )
            } header: {
                Text("Profile Visibility")
            } footer: {
                Text("Control what other traders can see. When private, others must request to follow you.")
            }

            Section {
                privacyNavigationRow(
                    title: "Blocked accounts",
                    value: summaryCount(viewModel.blockedCount),
                    route: .privacyBlockedAccounts
                )
                privacyNavigationRow(
                    title: "Muted accounts",
                    value: summaryCount(viewModel.mutedCount),
                    route: .privacyMutedAccounts
                )
                privacyNavigationRow(
                    title: "Who can message me",
                    value: viewModel.dmPrivacy.settingsTitle,
                    route: .privacyMessageAudience
                )
            } header: {
                Text("Safety")
            } footer: {
                Text("Block users to stop messaging and hide their content where applicable. Mute turns off notifications for a conversation.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(colors.groupedBackground.ignoresSafeArea())
        .experienceNavigationTitle("Privacy")
        .overlay {
            if viewModel.isProfileLoading || viewModel.isLoadingLists {
                ProgressView()
            }
        }
        .onAppear {
            viewModel.loadIfNeeded()
            Task { await viewModel.refreshSummary() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .userBlockListDidChange)) { _ in
            Task { await viewModel.refreshSummary() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mutedAccountsListDidChange)) { _ in
            Task { await viewModel.refreshSummary() }
        }
        .accessibilityIdentifier("settings.privacy")
    }

    private func privacyNavigationRow(title: String, value: String, route: SettingsRoute) -> some View {
        Button {
            ExperienceHaptics.play(.selection)
            stackNavigation?.pushSettings(route)
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .experienceStyle(.body, color: colors.primaryText)
                Spacer(minLength: ExperienceSpacing.sm)
                Text(value)
                    .experienceStyle(.body, color: colors.secondaryText)
                    .multilineTextAlignment(.trailing)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(colors.tertiaryText)
            }
            .padding(.vertical, ExperienceSpacing.xxs)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.privacy.row.\(route.rawValue)")
    }

    private func summaryCount(_ count: Int) -> String {
        count == 0 ? "None" : "\(count)"
    }
}
