import SwiftUI

struct SettingsAccountView: View {
    @State private var viewModel: SettingsAccountViewModel

    @Environment(\.stackNavigation) private var stackNavigation
    @Environment(\.themeColors) private var colors

    init(
        data: DataEnvironment,
        authenticationCoordinator: AuthenticationCoordinator,
        navigationCoordinator: NavigationCoordinator,
        profileStore: CurrentUserProfileStore? = nil
    ) {
        _viewModel = State(
            initialValue: SettingsAccountViewModel(
                profiles: data.profiles,
                billing: data.billing,
                account: data.account,
                session: data.session,
                authenticationCoordinator: authenticationCoordinator,
                navigationCoordinator: navigationCoordinator,
                profileStore: profileStore
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

            if let deleteError = viewModel.deleteErrorMessage {
                Section {
                    SettingsInlineError(message: deleteError) {
                        viewModel.clearDeleteError()
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
                Button {
                    ExperienceHaptics.play(.warning)
                    viewModel.requestDeleteAccount()
                } label: {
                    SettingsNavigationRow(
                        title: "Delete Account",
                        systemImage: "trash",
                        isDestructive: true,
                        showsChevron: false
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isDeletingAccount)
                .accessibilityLabel("Delete Account")
                .accessibilityHint("Permanently deletes your TradeTraxs account and associated data")
            } header: {
                Text("Delete Account")
            } footer: {
                Text("Permanently delete your TradeTraxs account and associated data.")
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
                .disabled(viewModel.isDeletingAccount)
            }
        }
        .listStyle(.insetGrouped)
        .experienceDashboardGroupedRows()
        .scrollContentBackground(.hidden)
        .background(colors.groupedBackground.ignoresSafeArea())
        .experienceNavigationTitle("Account")
        .overlay {
            if viewModel.isLoading || viewModel.isDeletingAccount {
                ProgressView(viewModel.isDeletingAccount ? "Deleting account…" : "")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(colors.groupedBackground.opacity(viewModel.isDeletingAccount ? 0.92 : 0))
                    .accessibilityIdentifier("settings.account.deleting")
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
        .confirmationDialog(
            "Delete your account?",
            isPresented: Binding(
                get: { viewModel.showsDeleteAccountExplainer },
                set: { isPresented in
                    if !isPresented, !viewModel.showsDeleteAccountConfirmation {
                        viewModel.cancelDeleteAccountFlow()
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Continue", role: .destructive) {
                viewModel.proceedToDeleteConfirmation()
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelDeleteAccountFlow()
            }
        } message: {
            Text(viewModel.deleteAccountExplainerMessage)
        }
        .confirmationDialog(
            "Delete Account",
            isPresented: Binding(
                get: { viewModel.showsDeleteAccountConfirmation },
                set: { isPresented in
                    if !isPresented, !viewModel.isDeletingAccount {
                        viewModel.cancelDeleteAccountFlow()
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                viewModel.confirmDeleteAccount()
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelDeleteAccountFlow()
            }
        } message: {
            Text(viewModel.deleteAccountConfirmationMessage)
        }
        .fullScreenCover(isPresented: Binding(
            get: { viewModel.showsDeleteAccountSuccess },
            set: { _ in }
        )) {
            AccountDeletionSuccessView {
                viewModel.returnToSignInAfterAccountDeletion()
            }
        }
        .accessibilityIdentifier("settings.account")
    }
}

private struct AccountDeletionSuccessView: View {
    let onReturnToSignIn: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(spacing: ExperienceSpacing.xl) {
            Spacer(minLength: ExperienceSpacing.xxl)

            ExperienceIcon(icon: .success, size: .xl, color: colors.accent)
                .accessibilityHidden(true)

            VStack(spacing: ExperienceSpacing.sm) {
                Text("Account Deleted")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .foregroundStyle(colors.primaryText)
                    .multilineTextAlignment(.center)

                Text("Your TradeTraxs account has been successfully deleted.")
                    .experienceStyle(.body, color: colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, ExperienceSpacing.xl)

            ExperienceButton(
                title: "Return to Sign In",
                kind: .primary,
                action: onReturnToSignIn
            )
            .padding(.horizontal, ExperienceSpacing.xl)
            .accessibilityIdentifier("settings.account.deletionSuccess.returnToSignIn")

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .experienceScreenBackground()
        .accessibilityIdentifier("settings.account.deletionSuccess")
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
                billing: data.billing,
                account: data.account,
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
        .experienceDashboardGroupedRows()
        .scrollContentBackground(.hidden)
        .background(colors.groupedBackground.ignoresSafeArea())
        .experienceNavigationTitle("Security")
        .onAppear { viewModel.loadIfNeeded() }
        .accessibilityIdentifier("settings.security")
    }
}
