import SwiftUI

struct SettingsPrivacyAccountRow: View {
    let profile: Profile
    let actionTitle: String
    var isActionDisabled: Bool = false
    let onAction: () -> Void
    let onOpenProfile: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            Button(action: onOpenProfile) {
                HStack(spacing: ExperienceSpacing.sm) {
                    ExperienceAvatar(
                        initials: String(profile.displayName.prefix(1)),
                        image: nil,
                        size: 44
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.displayName)
                            .experienceStyle(.body, color: colors.primaryText)
                            .lineLimit(1)
                        Text("@\(profile.username)")
                            .experienceStyle(.footnote, color: colors.secondaryText)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: ExperienceSpacing.xs)

            Button(actionTitle, action: onAction)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(colors.accent)
                .disabled(isActionDisabled)
        }
        .padding(.vertical, ExperienceSpacing.xxs)
        .accessibilityElement(children: .contain)
    }
}

struct SettingsBlockedAccountsView: View {
    @State private var viewModel: SettingsBlockedAccountsViewModel

    @Environment(\.themeColors) private var colors

    init(messages: any MessageRepository, navigationCoordinator: NavigationCoordinator) {
        _viewModel = State(
            initialValue: SettingsBlockedAccountsViewModel(
                messages: messages,
                navigationCoordinator: navigationCoordinator
            )
        )
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

            if viewModel.items.isEmpty, !viewModel.isLoading {
                Section {
                    Text("You haven't blocked anyone.")
                        .experienceStyle(.footnote, color: colors.secondaryText)
                }
            } else {
                Section {
                    ForEach(viewModel.items) { account in
                        SettingsPrivacyAccountRow(
                            profile: account.profile,
                            actionTitle: "Unblock",
                            isActionDisabled: viewModel.actionInFlight == account.id,
                            onAction: { viewModel.unblock(account) },
                            onOpenProfile: { viewModel.openProfile(account) }
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(colors.groupedBackground.ignoresSafeArea())
        .experienceNavigationTitle("Blocked Accounts")
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .onAppear { viewModel.loadIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .userBlockListDidChange)) { _ in
            Task { await viewModel.refresh() }
        }
        .accessibilityIdentifier("settings.privacy.blocked")
    }
}

struct SettingsMutedAccountsView: View {
    @State private var viewModel: SettingsMutedAccountsViewModel

    @Environment(\.themeColors) private var colors

    init(messages: any MessageRepository, navigationCoordinator: NavigationCoordinator) {
        _viewModel = State(
            initialValue: SettingsMutedAccountsViewModel(
                messages: messages,
                navigationCoordinator: navigationCoordinator
            )
        )
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

            if viewModel.items.isEmpty, !viewModel.isLoading {
                Section {
                    Text("Muted conversations will appear here.")
                        .experienceStyle(.footnote, color: colors.secondaryText)
                } footer: {
                    Text("Muting turns off notifications for a conversation. You can still read messages when you open the chat.")
                }
            } else {
                Section {
                    ForEach(viewModel.items) { peer in
                        SettingsPrivacyAccountRow(
                            profile: peer.profile,
                            actionTitle: "Unmute",
                            isActionDisabled: viewModel.actionInFlight == peer.id,
                            onAction: { viewModel.unmute(peer) },
                            onOpenProfile: { viewModel.openProfile(peer) }
                        )
                    }
                } footer: {
                    Text("Muting turns off notifications for a conversation. You can still read messages when you open the chat.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(colors.groupedBackground.ignoresSafeArea())
        .experienceNavigationTitle("Muted Accounts")
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .onAppear { viewModel.loadIfNeeded() }
        .accessibilityIdentifier("settings.privacy.muted")
    }
}

struct SettingsDmPrivacyPickerView: View {
    @Bindable var viewModel: SettingsPrivacyViewModel

    @Environment(\.themeColors) private var colors

    var body: some View {
        List {
            Section {
                ForEach(DmPrivacy.allCases, id: \.self) { option in
                    Button {
                        viewModel.updateDmPrivacy(option)
                    } label: {
                        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                                Text(option.settingsTitle)
                                    .experienceStyle(.body, color: colors.primaryText)
                                Text(option.settingsSubtitle)
                                    .experienceStyle(.footnote, color: colors.secondaryText)
                            }
                            Spacer(minLength: ExperienceSpacing.xs)
                            if viewModel.dmPrivacy == option {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(colors.accent)
                            }
                        }
                        .padding(.vertical, ExperienceSpacing.xxs)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.privacy.dm.\(option.rawValue)")
                }
            } header: {
                Text("Who can message me")
            } footer: {
                Text("This applies to new direct messages. Existing conversations are not affected.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(colors.groupedBackground.ignoresSafeArea())
        .experienceNavigationTitle("Who Can Message Me")
        .onAppear {
            Task { await viewModel.refreshSummary() }
        }
        .accessibilityIdentifier("settings.privacy.dmPrivacy")
    }
}
