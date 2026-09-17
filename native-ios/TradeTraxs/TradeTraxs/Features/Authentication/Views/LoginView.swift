import SwiftUI

struct LoginView: View {
    @State private var viewModel: LoginViewModel
    let navigationCoordinator: NavigationCoordinator

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedField: AuthLoginField?

    init(
        authenticationCoordinator: AuthenticationCoordinator,
        navigationCoordinator: NavigationCoordinator,
        allowsDevelopmentBypass: Bool
    ) {
        _viewModel = State(
            initialValue: LoginViewModel(
                authenticationCoordinator: authenticationCoordinator,
                allowsDevelopmentBypass: allowsDevelopmentBypass
            )
        )
        self.navigationCoordinator = navigationCoordinator
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        brandingHeader
                            .padding(.bottom, ExperienceSpacing.sm)
                            .onTapGesture { releaseLoginKeyboardFocus() }

                        modeSwitchRow
                            .padding(.bottom, viewModel.mode == .signUp ? ExperienceSpacing.sm : ExperienceSpacing.md)

                        social
                            .padding(.bottom, ExperienceSpacing.sm)

                        credentials

                        if viewModel.mode == .signUp {
                            AuthLegalAgreementFootnote(presentation: .createAccountAgreement)
                                .padding(.top, ExperienceSpacing.sm)
                        }

                        primaryAction
                            .padding(.top, viewModel.mode == .signUp ? ExperienceSpacing.xs : ExperienceSpacing.md)

                        if viewModel.mode == .signIn {
                            forgotPasswordLink
                                .padding(.top, ExperienceSpacing.xxs)
                        }

                        exploreTradeTraxsAction
                            .padding(
                                .top,
                                viewModel.mode == .signUp ? ExperienceSpacing.lg : ExperienceSpacing.xxs
                            )
                    }

                    Spacer(minLength: ExperienceSpacing.sm)

                    AuthLegalAgreementFootnote(presentation: .footerLinks)
                        .padding(.bottom, ExperienceSpacing.sm)
                }
                .experiencePadding(.lg)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height, alignment: .top)
                .padding(.top, ExperienceSpacing.sm)
            }
            .experienceFormScrollKeyboard()
        }
        .experienceScreenBackground()
        .experienceKeyboardDismissOnTapOutside()
        .experienceFormKeyboard(focus: $focusedField, releaseOnDisappear: false)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            StartupTrace.event("LoginView.body.onAppear")
            LoginFocusProbe.installKeyboardObserversIfNeeded()
            let appliedDemoExitIntent = applyDemoExitAuthIntentIfNeeded()
            if !appliedDemoExitIntent {
                applyFreshInstallLandingModeIfNeeded()
            }
            AuthLandingInstallState.shared.recordLoggedOutAuthLandingPresented()
        }
        .onDisappear {
            releaseLoginKeyboardFocus()
        }
        .onChange(of: viewModel.isSubmitting) { _, isSubmitting in
            if isSubmitting {
                releaseLoginKeyboardFocus()
            }
        }
        .onChange(of: viewModel.mode) { _, _ in
            releaseLoginKeyboardFocus()
        }
        .onChange(of: AppLaunchController.shared.bootstrapGeneration) { _, _ in
            let appliedDemoExitIntent = applyDemoExitAuthIntentIfNeeded()
            if !appliedDemoExitIntent {
                applyFreshInstallLandingModeIfNeeded()
            }
        }
        .onChange(of: focusedField) { _, newValue in
            switch newValue {
            case .name:
                LoginFocusProbe.focused(field: "name")
            case .email:
                LoginFocusProbe.focused(field: "email")
            case .password:
                LoginFocusProbe.focused(field: "password")
            case nil:
                break
            }
        }
    }

    private var brandingHeader: some View {
        VStack(alignment: .center, spacing: ExperienceSpacing.sm) {
            Image("AppLogo")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .accessibilityHidden(true)

            Text("TradeTraxs")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(colors.primaryText)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity)
    }

    private var modeSwitchRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.xs) {
            if viewModel.mode == .signIn {
                Text("Sign in to your Account")
                    .font(ExperienceTypography.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(colors.primaryText)
                Text("or")
                    .font(ExperienceTypography.callout)
                    .foregroundStyle(colors.secondaryText)
                alternateModeButton("Create Account")
            } else {
                Text("Create Account")
                    .font(ExperienceTypography.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(colors.primaryText)
                Text("or")
                    .font(ExperienceTypography.callout)
                    .foregroundStyle(colors.secondaryText)
                alternateModeButton("Sign in to your Account")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .animation(
            ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
            value: viewModel.mode
        )
    }

    private func alternateModeButton(_ title: String) -> some View {
        Button {
            releaseLoginKeyboardFocus()
            viewModel.toggleMode()
        } label: {
            Text(title)
                .font(ExperienceTypography.callout)
                .fontWeight(.semibold)
                .foregroundStyle(colors.accent)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("auth.toggleMode")
    }

    private var credentials: some View {
        VStack(spacing: ExperienceSpacing.sm) {
            if viewModel.mode == .signUp {
                AuthTextField(
                    title: "Name",
                    text: $viewModel.fullName,
                    kind: .name,
                    textContentType: .name,
                    submitLabel: .next,
                    onSubmit: { focusedField = .email },
                    loginField: .name,
                    loginFocusedField: $focusedField
                )
            }

            AuthTextField(
                title: "Email",
                text: $viewModel.email,
                kind: .email,
                textContentType: .username,
                submitLabel: .next,
                onSubmit: { focusedField = .password },
                loginField: .email,
                loginFocusedField: $focusedField
            )

            AuthTextField(
                title: viewModel.mode == .signUp ? "Create Password" : "Password",
                text: $viewModel.password,
                kind: viewModel.mode == .signUp ? .newPassword : .password,
                isSecureVisible: $viewModel.isSecurePasswordVisible,
                textContentType: viewModel.mode == .signUp ? .newPassword : .password,
                submitLabel: .go,
                onSubmit: {
                    Task { await viewModel.submit() }
                },
                loginField: .password,
                loginFocusedField: $focusedField
            )

            authFeedback
        }
        .padding(.top, viewModel.mode == .signUp ? ExperienceSpacing.xxs : 0)
    }

    @ViewBuilder
    private var authFeedback: some View {
        if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .experienceStyle(.footnote, color: colors.error)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("auth.error")
        }

        if let informationalMessage = viewModel.informationalMessage {
            Text(informationalMessage)
                .experienceStyle(.footnote, color: colors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("auth.confirmationPending")
        }

        if viewModel.pendingConfirmationEmail != nil {
            Button {
                Task { await viewModel.resendConfirmationEmail() }
            } label: {
                if viewModel.isResendingConfirmation {
                    ProgressView()
                } else {
                    Text("Resend confirmation email")
                }
            }
            .font(ExperienceTypography.footnote)
            .foregroundStyle(colors.accent)
            .frame(minHeight: ExperienceAccessibility.minTouchTarget)
            .disabled(viewModel.isResendingConfirmation)
            .accessibilityIdentifier("auth.resendConfirmation")
        }

        if let confirmationResentMessage = viewModel.confirmationResentMessage {
            Text(confirmationResentMessage)
                .experienceStyle(.footnote, color: colors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("auth.confirmationResent")
        }
    }

    private var primaryAction: some View {
        ExperienceButton(
            title: viewModel.primaryButtonTitle,
            kind: .primary,
            isEnabled: !viewModel.isSubmitting,
            isLoading: viewModel.isSubmitting,
            accessibilityIdentifier: "auth.submit"
        ) {
            Task { await viewModel.submit() }
        }
    }

    private var forgotPasswordLink: some View {
        HStack {
            Spacer()
            Button("Forgot Password?") {
                ExperienceHaptics.play(.selection)
                releaseLoginKeyboardFocus()
                navigationCoordinator.open(.auth(.resetPassword))
            }
            .font(ExperienceTypography.subheadline)
            .foregroundStyle(colors.accent)
            .frame(minHeight: ExperienceAccessibility.minTouchTarget)
            .accessibilityIdentifier("auth.forgotPassword")
        }
    }

    private var social: some View {
        SocialSignInButtons(
            isEnabled: !viewModel.isSubmitting && !viewModel.isOAuthInteractionInFlight,
            isLoading: viewModel.isSubmitting || viewModel.isOAuthInteractionInFlight,
            onAppleInteractionBegan: {
                viewModel.beginOAuthProviderInteraction()
            },
            onAppleCredential: { credential in
                releaseLoginKeyboardFocus()
                Task { await viewModel.signInWithApple(credential: credential) }
            },
            onAppleCancelled: {
                viewModel.handleAppleSignInCancelled()
            },
            onAppleFailure: { error in
                viewModel.handleAppleSignInFailure(error)
            },
            onGoogleInteractionBegan: {
                viewModel.beginOAuthProviderInteraction()
            },
            onGoogle: {
                releaseLoginKeyboardFocus()
                Task { await viewModel.signInWithGoogle() }
            }
        )
    }

    private var exploreTradeTraxsAction: some View {
        ExperienceButton(
            title: "Explore as Guest",
            kind: .secondary,
            accessibilityIdentifier: "auth.exploreDemo"
        ) {
            releaseLoginKeyboardFocus()
            AppLaunchController.shared.enterDemoExplore()
        }
    }

    private func releaseLoginKeyboardFocus() {
        ExperienceKeyboard.dismissFormKeyboard()
    }

    @discardableResult
    private func applyDemoExitAuthIntentIfNeeded() -> Bool {
        guard let intent = AppLaunchController.shared.consumeDemoExitAuthIntent() else { return false }
        switch intent {
        case .signIn:
            viewModel.mode = .signIn
        case .createAccount:
            viewModel.mode = .signUp
        }
        return true
    }

    /// First logged-out landing only — returning users already default to Sign In via ``AuthLandingInstallState``.
    private func applyFreshInstallLandingModeIfNeeded() {
        guard AuthLandingInstallState.shared.initialLoginMode == .signUp else { return }
        viewModel.mode = .signUp
    }
}
