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

            if let exportError = viewModel.exportErrorMessage {
                Section {
                    SettingsInlineError(message: exportError) {
                        viewModel.clearExportError()
                    }
                }
            }

            Section {
                SettingsInfoRow(title: "Email", value: viewModel.email ?? "–")
                SettingsInfoRow(title: "Username", value: viewModel.username.map { "@\($0)" } ?? "–")
                if let createdAt = viewModel.createdAt {
                    SettingsInfoRow(
                        title: "Member since",
                        value: createdAt.formatted(date: .abbreviated, time: .omitted)
                    )
                }

                if !AppLaunchController.shared.isDemoExperienceActive {
                    Button {
                        ExperienceHaptics.play(.selection)
                        stackNavigation?.pushSettings(.security)
                    } label: {
                        SettingsNavigationRow(title: "Password & Security", systemImage: "lock.shield")
                    }
                    .buttonStyle(.experiencePlain)

                    Button {
                        ExperienceHaptics.play(.selection)
                        viewModel.downloadAccountData()
                    } label: {
                        SettingsNavigationRow(
                            title: "Download Account Data",
                            systemImage: "square.and.arrow.down",
                            showsChevron: false
                        )
                        .overlay(alignment: .trailing) {
                            if viewModel.isExportingAccountData {
                                ExperienceIndeterminateProgress()
                                    .accessibilityIdentifier("settings.account.downloading")
                            }
                        }
                    }
                    .buttonStyle(.experiencePlain)
                    .disabled(viewModel.isDeletingAccount || viewModel.isExportingAccountData || viewModel.exportShareItem != nil)
                    .accessibilityLabel("Download Account Data")
                    .accessibilityIdentifier("settings.account.downloadData")

                    Button {
                        viewModel.confirmsLogout = true
                    } label: {
                        SettingsNavigationRow(
                            title: "Log Out",
                            systemImage: "rectangle.portrait.and.arrow.right",
                            isDestructive: true
                        )
                    }
                    .buttonStyle(.experiencePlain)
                    .disabled(viewModel.isDeletingAccount)
                }
            } header: {
                Text("Account Information")
            }

            if !AppLaunchController.shared.isDemoExperienceActive {
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
                    .buttonStyle(.experiencePlain)
                    .disabled(viewModel.isDeletingAccount)
                    .accessibilityLabel("Delete Account")
                    .accessibilityHint("Permanently deletes your TradeTraxs account and associated data")
                } footer: {
                    Text("Permanently delete your TradeTraxs account and associated data.")
                }
            }
        }
        .experienceInsetGroupedListStyle(pageBackground: true)
        .experienceNavigationTitle("Account")
        .overlay {
            if viewModel.isLoading || viewModel.isDeletingAccount {
                ExperienceLoadingOverlay(
                    message: viewModel.isDeletingAccount ? "Deleting account…" : nil
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(colors.groupedBackground.opacity(viewModel.isDeletingAccount ? 0.92 : 0))
                .accessibilityIdentifier("settings.account.deleting")
            }
        }
        .onAppear { viewModel.loadIfNeeded() }
        .sheet(
            isPresented: Binding(
                get: { viewModel.exportShareItem != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.clearExportShare()
                    }
                }
            )
        ) {
            if let url = viewModel.exportShareItem?.url {
                AccountDataShareSheet(items: [url])
            }
        }
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
        .sheet(isPresented: Binding(
            get: { viewModel.showsAppleSubscriptionDeletionWarning },
            set: { isPresented in
                if !isPresented, !viewModel.showsDeleteAccountConfirmation {
                    viewModel.cancelDeleteAccountFlow()
                }
            }
        )) {
            AppleSubscriptionDeletionWarningSheet(
                message: viewModel.appleSubscriptionDeletionWarningMessage,
                onManageSubscription: {
                    Task { await viewModel.manageAppleSubscription() }
                },
                onContinueDeleting: {
                    viewModel.proceedFromAppleSubscriptionDeletionWarning()
                },
                onCancel: {
                    viewModel.cancelDeleteAccountFlow()
                }
            )
            .experienceSheetChrome(detents: [.medium])
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
        .fullScreenCover(isPresented: Binding(
            get: { viewModel.showsDeleteAccountConfirmation },
            set: { _ in }
        )) {
            AccountDeletionFinalConfirmationView(
                title: viewModel.deleteAccountFinalConfirmationTitle,
                message: viewModel.deleteAccountFinalConfirmationMessage,
                isDeleting: viewModel.isDeletingAccount,
                onKeepAccount: { viewModel.cancelDeleteAccountFlow() },
                onHoldToDeleteComplete: { viewModel.confirmDeleteAccount() }
            )
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

/// Full-screen final delete confirmation, shown alone after the first alert.
private struct AccountDeletionFinalConfirmationView: View {
    let title: String
    let message: String
    let isDeleting: Bool
    let onKeepAccount: () -> Void
    let onHoldToDeleteComplete: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: ExperienceSpacing.xl)

            VStack(spacing: ExperienceSpacing.lg) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(colors.loss)
                    .accessibilityHidden(true)

                VStack(spacing: ExperienceSpacing.sm) {
                    Text(title)
                        .experienceStyle(.title3, color: colors.primaryText)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .experienceStyle(.footnote, color: colors.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: ExperienceSpacing.sm) {
                    Button(action: onKeepAccount) {
                        Text("Keep My Account")
                            .experienceStyle(.body, color: colors.onAccent)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .frame(height: HoldToPermanentlyDeleteControl.preferredHeight)
                            .background(colors.accent, in: RoundedRectangle(
                                cornerRadius: ExperienceRadius.md,
                                style: .continuous
                            ))
                    }
                    .buttonStyle(.plain)
                    .disabled(isDeleting)
                    .accessibilityIdentifier("settings.account.deleteFinal.keep")

                    HoldToPermanentlyDeleteControl(
                        isEnabled: !isDeleting,
                        isProcessing: isDeleting,
                        onHoldComplete: onHoldToDeleteComplete
                    )
                    .accessibilityIdentifier("settings.account.deleteFinal.hold")
                }
                .padding(.top, ExperienceSpacing.xs)
            }
            .padding(.horizontal, ExperienceSpacing.xl)
            .frame(maxWidth: 440)

            Spacer(minLength: ExperienceSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .experienceScreenBackground()
        .interactiveDismissDisabled(isDeleting)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("settings.account.deleteFinal.overlay")
    }
}

/// Five-second continuous press with red fill progress; resets on release or backgrounding.
private struct HoldToPermanentlyDeleteControl: View {
    private static let holdDuration: TimeInterval = 5
    fileprivate static let preferredHeight: CGFloat = 54

    let isEnabled: Bool
    let isProcessing: Bool
    let onHoldComplete: () -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.scenePhase) private var scenePhase
    @State private var progress: CGFloat = 0
    @State private var holdStart: Date?
    @State private var tickTask: Task<Void, Never>?

    private var buttonShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            buttonShape
                .fill(colors.loss)

            buttonShape
                .fill(Color.red.opacity(0.55))
                .scaleEffect(x: max(progress, 0.001), y: 1, anchor: .leading)

            Group {
                if isProcessing {
                    ExperienceIndeterminateProgress()
                        .tint(colors.textInverse)
                } else {
                    Text("Hold 5 Seconds to Delete")
                        .experienceStyle(.body, color: colors.textInverse)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.preferredHeight)
        .clipShape(buttonShape)
        .contentShape(buttonShape)
        .opacity(isEnabled && !isProcessing ? 1 : 0.6)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard isEnabled, !isProcessing else { return }
                    if holdStart == nil {
                        beginHold()
                    }
                }
                .onEnded { _ in
                    cancelHold()
                }
        )
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                cancelHold()
            }
        }
        .accessibilityLabel("Hold five seconds to permanently delete account")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func beginHold() {
        holdStart = Date()
        progress = 0
        tickTask?.cancel()
        tickTask = Task { @MainActor in
            while !Task.isCancelled, let started = holdStart {
                let elapsed = Date().timeIntervalSince(started)
                let next = min(1, CGFloat(elapsed / Self.holdDuration))
                progress = next
                if next >= 1 {
                    holdStart = nil
                    progress = 0
                    ExperienceHaptics.play(.success)
                    onHoldComplete()
                    return
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    private func cancelHold() {
        tickTask?.cancel()
        tickTask = nil
        holdStart = nil
        progress = 0
    }
}

private struct AppleSubscriptionDeletionWarningSheet: View {
    let message: String
    let onManageSubscription: () -> Void
    let onContinueDeleting: () -> Void
    let onCancel: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title3)
                            .foregroundStyle(colors.warning)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                            Text("Apple Subscription")
                                .experienceStyle(.headline, color: colors.primaryText)
                            Text(message)
                                .experienceStyle(.footnote, color: colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, ExperienceSpacing.xxs)
                }

                Section {
                    Button(action: onManageSubscription) {
                        SettingsPrimaryActionLabel(
                            title: "Manage Subscription",
                            systemImage: "arrow.up.right.square"
                        )
                    }
                    .buttonStyle(.experiencePlain)
                    .accessibilityIdentifier("settings.account.deleteApple.manageSubscription")

                    Button(action: onContinueDeleting) {
                        Text("Continue Deleting Account")
                            .experienceStyle(.body, color: colors.loss)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, ExperienceSpacing.xxs)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.experiencePlain)
                    .accessibilityIdentifier("settings.account.deleteApple.continue")
                }

                Section {
                    Button("Cancel", role: .cancel, action: onCancel)
                        .accessibilityIdentifier("settings.account.deleteApple.cancel")
                }
            }
            .experienceInsetGroupedListStyle(pageBackground: true)
            .experienceNavigationTitle("Delete Account")
        }
        .accessibilityIdentifier("settings.account.deleteApple.warning")
    }
}

private struct AccountDataShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
                SettingsInfoRow(title: "Email", value: viewModel.email ?? "–")
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
                .buttonStyle(.experiencePlain)
                .disabled(viewModel.email?.isEmpty != false)
            } footer: {
                Text(viewModel.passwordResetMessage ?? "You’ll get an email with steps to choose a new password.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }
        }
        .experienceInsetGroupedListStyle(pageBackground: true)
        .experienceNavigationTitle("Security")
        .onAppear { viewModel.loadIfNeeded() }
        .accessibilityIdentifier("settings.security")
    }
}
