import SwiftUI

/// Set-password step opened from a Supabase recovery Universal Link.
struct SetNewPasswordView: View {
    @Bindable var model: PasswordRecoveryModel
    let authenticationCoordinator: AuthenticationCoordinator

    @State private var password = ""
    @State private var confirmation = ""
    @State private var isSecureVisible = false
    @Environment(\.themeColors) private var colors

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xl) {
                switch model.phase {
                case .hidden, .verifying:
                    verifying
                case .ready:
                    form
                case .invalid(let message):
                    invalid(message)
                case .success(let signedIn):
                    success(signedIn: signedIn)
                }
            }
            .experiencePadding(.xl)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .experienceScreenBackground()
        .experienceNavigationTitle("Set New Password")
        .onDisappear {
            ExperienceKeyboard.dismissFormKeyboard()
        }
    }

    private var verifying: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            ProgressView()
            Text("Verifying password reset link…")
                .experienceStyle(.body, color: colors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, ExperienceSpacing.lg)
        .accessibilityIdentifier("auth.reset.verifying")
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
            Text("Choose a new password for your account.")
                .experienceStyle(.body, color: colors.secondaryText)

            AuthTextField(
                title: "New Password",
                text: $password,
                kind: .newPassword,
                isSecureVisible: $isSecureVisible,
                textContentType: .newPassword,
                submitLabel: .next
            )
            .accessibilityIdentifier("auth.reset.newPassword")

            AuthTextField(
                title: "Confirm Password",
                text: $confirmation,
                kind: .newPassword,
                isSecureVisible: $isSecureVisible,
                textContentType: .newPassword,
                submitLabel: .done,
                onSubmit: { Task { await save() } }
            )
            .accessibilityIdentifier("auth.reset.confirm")

            if let formError = model.formError {
                Text(formError)
                    .experienceStyle(.footnote, color: colors.error)
                    .accessibilityIdentifier("auth.reset.formError")
            }

            ExperienceButton(
                title: "Update Password",
                kind: .primary,
                isEnabled: !model.isSaving,
                isLoading: model.isSaving,
                accessibilityIdentifier: "auth.reset.save"
            ) {
                Task { await save() }
            }
        }
        .padding(.top, ExperienceSpacing.sm)
    }

    private func invalid(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
            Text(message)
                .experienceStyle(.body, color: colors.primaryText)
                .accessibilityIdentifier("auth.reset.invalid")
            RequestAnotherResetLink(authenticationCoordinator: authenticationCoordinator)
        }
        .padding(.top, ExperienceSpacing.sm)
    }

    private func success(signedIn: Bool) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
            Text("Your password was updated.")
                .experienceStyle(.headline, color: colors.primaryText)
            Text(
                signedIn
                    ? "You can continue in TradeTraxs."
                    : "Sign in with your new password."
            )
            .experienceStyle(.body, color: colors.secondaryText)
            ExperienceButton(
                title: "Continue",
                kind: .primary,
                accessibilityIdentifier: "auth.reset.continue"
            ) {
                password = ""
                confirmation = ""
                model.dismiss()
            }
        }
        .padding(.top, ExperienceSpacing.sm)
        .accessibilityIdentifier("auth.reset.success")
    }

    private func save() async {
        await model.save(password: password, confirmation: confirmation)
        if case .success = model.phase {
            password = ""
            confirmation = ""
        }
    }

}

private struct RequestAnotherResetLink: View {
    @State private var viewModel: ResetPasswordViewModel
    @Environment(\.themeColors) private var colors

    init(authenticationCoordinator: AuthenticationCoordinator) {
        _viewModel = State(
            initialValue: ResetPasswordViewModel(
                authenticationCoordinator: authenticationCoordinator
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
            AuthTextField(
                title: "Email",
                text: $viewModel.email,
                kind: .email,
                textContentType: .username,
                submitLabel: .send,
                onSubmit: { Task { await viewModel.submit() } }
            )

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .experienceStyle(.footnote, color: colors.error)
            }
            if viewModel.didSucceed {
                Text("If an account exists for that email, a reset link is on the way.")
                    .experienceStyle(.body, color: colors.secondaryText)
            }

            ExperienceButton(
                title: "Request a new link",
                kind: .primary,
                isEnabled: true,
                isLoading: viewModel.isSubmitting,
                accessibilityIdentifier: "auth.reset.request"
            ) {
                Task { await viewModel.submit() }
            }
        }
    }
}
