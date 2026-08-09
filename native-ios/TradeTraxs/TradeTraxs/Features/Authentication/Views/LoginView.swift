import SwiftUI

struct LoginView: View {
    @State private var viewModel: LoginViewModel
    let navigationCoordinator: NavigationCoordinator

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .animation(
            ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
            value: viewModel.mode
        )
        .animation(
            ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
            value: viewModel.errorMessage
        )
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
    }

    private var social: some View {
        SocialSignInButtons(
            isEnabled: !viewModel.isSubmitting,
            isLoading: viewModel.isSubmitting,
            onApple: {
                Task { await viewModel.signInWithApple() }
            },
            onGoogle: {
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
                submitLabel: .next
            )

            AuthTextField(
                title: "Password",
                text: $viewModel.password,
                kind: viewModel.mode == .signUp ? .newPassword : .password,
                isSecureVisible: $viewModel.isSecurePasswordVisible,
                textContentType: viewModel.mode == .signUp ? .newPassword : .password,
                submitLabel: .go,
                onSubmit: {
                    Task { await viewModel.submit() }
                }
            )

            if viewModel.mode == .signIn {
                HStack {
                    Spacer()
                    Button("Forgot password?") {
                        ExperienceHaptics.play(.selection)
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
            }

            if let informationalMessage = viewModel.informationalMessage {
                Text(informationalMessage)
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
            Button {
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
}
