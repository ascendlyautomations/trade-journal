import SwiftUI

struct SettingsAccountView: View {
    @State private var viewModel: SettingsAccountViewModel

    @Environment(\.stackNavigation) private var stackNavigation
    @Environment(\.themeColors) private var colors

    init(
        data: DataEnvironment,
        authenticationCoordinator: AuthenticationCoordinator,
        navigationCoordinator: NavigationCoordinator
    ) {
        _viewModel = State(
            initialValue: SettingsAccountViewModel(
                profiles: data.profiles,
                session: data.session,
                authenticationCoordinator: authenticationCoordinator,
                navigationCoordinator: navigationCoordinator
            )
        )
    }

    init(viewModel: SettingsAccountViewModel) {
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
                SettingsInfoRow(title: "Email", value: viewModel.email ?? "—")
                SettingsInfoRow(title: "Username", value: viewModel.username.map { "@\($0)" } ?? "—")
                if let createdAt = viewModel.createdAt {
                    SettingsInfoRow(
                        title: "Member since",
                        value: createdAt.formatted(date: .abbreviated, time: .omitted)
                    )
                }
            } header: {
                Text("Account Information")
            } footer: {
                Text("Your sign-in email and public username.")
            }

            Section("Security") {
                Button {
                    ExperienceHaptics.play(.selection)
                    stackNavigation?.pushSettings(.security)
                } label: {
                    SettingsNavigationRow(title: "Password & Security", systemImage: "lock.shield")
                }
                .buttonStyle(.plain)
            }

            Section {
                SettingsIntroBlock(
                    title: "Need to delete your account?",
                    message: "Account deletion is available in Settings on the TradeTraxs website. Contact support if you need help."
                )
            } header: {
                Text("Delete Account")
            }

            Section {
                Button {
                    viewModel.confirmsLogout = true
                } label: {
                    SettingsNavigationRow(
                        title: "Log Out",
                        systemImage: "rectangle.portrait.and.arrow.right",
                        isDestructive: true
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(colors.groupedBackground.ignoresSafeArea())
        .experienceNavigationTitle("Account")
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .onAppear { viewModel.loadIfNeeded() }
        .confirmationDialog(
            "Log out of TradeTraxs?",
            isPresented: Binding(
                get: { viewModel.confirmsLogout },
                set: { viewModel.confirmsLogout = $0 }
            ),
            titleVisibility: .visible
        ) {
            Button("Log Out", role: .destructive) { viewModel.logout() }
            Button("Cancel", role: .cancel) {}
        }
        .accessibilityIdentifier("settings.account")
    }
}

struct SettingsSecurityView: View {
    @State private var viewModel: SettingsAccountViewModel

    @Environment(\.themeColors) private var colors

    init(
        data: DataEnvironment,
        authenticationCoordinator: AuthenticationCoordinator,
        navigationCoordinator: NavigationCoordinator
    ) {
        _viewModel = State(
            initialValue: SettingsAccountViewModel(
                profiles: data.profiles,
                session: data.session,
                authenticationCoordinator: authenticationCoordinator,
                navigationCoordinator: navigationCoordinator
            )
        )
    }

    init(viewModel: SettingsAccountViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        List {
            Section {
                SettingsInfoRow(title: "Email", value: viewModel.email ?? "—")
            } header: {
                Text("Sign-In")
            } footer: {
                Text("We’ll send a reset link to this email address.")
            }

            Section {
                Button {
                    viewModel.requestPasswordReset()
                } label: {
                    SettingsPrimaryActionLabel(title: "Send Password Reset Email", systemImage: "envelope")
                }
                .buttonStyle(.plain)
                .disabled(viewModel.email?.isEmpty != false)
            } footer: {
                Text(viewModel.passwordResetMessage ?? "You’ll get an email with steps to choose a new password.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(colors.groupedBackground.ignoresSafeArea())
        .experienceNavigationTitle("Security")
        .onAppear { viewModel.loadIfNeeded() }
        .accessibilityIdentifier("settings.security")
    }
}
