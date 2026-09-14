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
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xl) {
                header
                social
                AuthDivider()
                form
                actions
                footer
            }
            .experiencePadding(.xl)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .experienceScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            StartupTrace.event("LoginView.body.onAppear")
            LoginFocusProbe.installKeyboardObserversIfNeeded()
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
        .onChange(of: focusedField) { _, newValue in
            switch newValue {
            case .email:
                LoginFocusProbe.focused(field: "email")
            case .password:
                LoginFocusProbe.focused(field: "password")
            case nil:
                break
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("TradeTraxs")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(colors.primaryText)
                .accessibilityAddTraits(.isHeader)

            Text(viewModel.mode == .signIn ? "Welcome back" : "Create your account")
                .experienceStyle(.title2, color: colors.primaryText)

            Text(
                viewModel.mode == .signIn
                    ? "Sign in to continue your journal."
                    : "Start journaling trades in seconds."
            )
            .experienceStyle(.body, color: colors.secondaryText)
        }
        .padding(.top, ExperienceSpacing.xxl)
        .animation(
            ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
            value: viewModel.mode
        )
    }

    private var social: some View {
        SocialSignInButtons(
            isEnabled: !viewModel.isSubmitting,
            isLoading: viewModel.isSubmitting,
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
            onGoogle: {
                releaseLoginKeyboardFocus()
                Task { await viewModel.signInWithGoogle() }
            }
        )
    }

    private var form: some View {
        VStack(spacing: ExperienceSpacing.md) {
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
                title: "Password",
                text: $viewModel.password,
                kind: viewModel.mode == .signUp ? .newPassword : .password,
                isSecureVisible: $viewModel.isSecurePasswordVisible,
                textContentType: viewModel.mode == .signUp ? .newPassword : .password,
                submitLabel: .go,
                onSubmit: {
                    releaseLoginKeyboardFocus()
                    Task { await viewModel.submit() }
                },
                loginField: .password,
                loginFocusedField: $focusedField
            )

            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-uitesting-login-native-ab") {
                loginNativeABControls
            }
            #endif

            if viewModel.mode == .signIn {
                HStack {
                    Spacer()
                    Button("Forgot password?") {
                        ExperienceHaptics.play(.selection)
                        releaseLoginKeyboardFocus()
                        navigationCoordinator.open(.auth(.resetPassword))
                    }
                    .font(ExperienceTypography.footnote)
                    .foregroundStyle(colors.accent)
                    .frame(minHeight: ExperienceAccessibility.minTouchTarget)
                    .accessibilityIdentifier("auth.forgotPassword")
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .experienceStyle(.footnote, color: colors.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("auth.error")
                    .animation(
                        ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
                        value: viewModel.errorMessage
                    )
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
                .accessibilityLabel("Resend confirmation email")
                .accessibilityIdentifier("auth.resendConfirmation")
            }

            if let confirmationResentMessage = viewModel.confirmationResentMessage {
                Text(confirmationResentMessage)
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("auth.confirmationResent")
            }
        }
    }

    private var actions: some View {
        VStack(spacing: ExperienceSpacing.sm) {
            ExperienceButton(
                title: viewModel.primaryButtonTitle,
                kind: .primary,
                isEnabled: viewModel.canSubmit,
                isLoading: viewModel.isSubmitting,
                accessibilityIdentifier: "auth.submit"
            ) {
                releaseLoginKeyboardFocus()
                Task { await viewModel.submit() }
            }

            if viewModel.showsDevelopmentContinue {
                ExperienceButton(
                    title: "Continue (Debug)",
                    kind: .secondary,
                    isEnabled: !viewModel.isSubmitting,
                    isLoading: false,
                    accessibilityIdentifier: "auth.continue"
                ) {
                    Task { await viewModel.continueAsDevelopment() }
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: ExperienceSpacing.md) {
            AuthLegalAgreementFootnote()
                .padding(.top, ExperienceSpacing.sm)

            Button {
                releaseLoginKeyboardFocus()
                viewModel.toggleMode()
            } label: {
                (
                    Text(viewModel.mode == .signIn ? "New here? " : "Already have an account? ")
                        + Text(viewModel.mode == .signIn ? "Create account" : "Sign in")
                        .foregroundColor(colors.accent)
                )
                .experienceStyle(.callout, color: colors.secondaryText)
                .frame(minHeight: ExperienceAccessibility.minTouchTarget)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("auth.toggleMode")

            Button("Take a quick tour") {
                ExperienceHaptics.play(.selection)
                releaseLoginKeyboardFocus()
                navigationCoordinator.open(.auth(.onboarding))
            }
            .font(ExperienceTypography.footnote)
            .foregroundStyle(colors.secondaryText)
            .frame(minHeight: ExperienceAccessibility.minTouchTarget)
            .accessibilityIdentifier("auth.onboarding")
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, ExperienceSpacing.xxl)
    }

    #if DEBUG
    /// Plain SwiftUI controls for A/B against ``AuthTextField`` — launch arg `-uitesting-login-native-ab`.
    private var loginNativeABControls: some View {
        LoginNativeABControls(isSignUp: viewModel.mode == .signUp)
            .padding(.top, ExperienceSpacing.md)
    }
    #endif

    /// Ends RTI/text session before OAuth, navigation, or auth state tears down Login.
    private func releaseLoginKeyboardFocus() {
        focusedField = nil
        ExperienceKeyboard.dismiss()
    }
}

#if DEBUG
/// Isolated A/B fields — separate text/focus from production ``AuthTextField`` controls.
private struct LoginNativeABControls: View {
    let isSignUp: Bool
    @State private var abEmail = ""
    @State private var abPassword = ""
    @FocusState private var abFocusedField: AuthLoginField?

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Native A/B (DEBUG)")
                .experienceStyle(.caption, color: colors.secondaryText)
            TextField("AB Email", text: $abEmail)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($abFocusedField, equals: .email)
            SecureField("AB Password", text: $abPassword)
                .textContentType(isSignUp ? .newPassword : .password)
                .focused($abFocusedField, equals: .password)
        }
    }
}
#endif
