import SwiftUI

struct ResetPasswordView: View {
    @State private var viewModel: ResetPasswordViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors

    init(authenticationCoordinator: AuthenticationCoordinator) {
        _viewModel = State(
            initialValue: ResetPasswordViewModel(
                authenticationCoordinator: authenticationCoordinator
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xl) {
                VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                    Text("Reset password")
                        .experienceStyle(.largeTitle, color: colors.primaryText)
                    Text("We’ll email you a secure link to choose a new password.")
                        .experienceStyle(.body, color: colors.secondaryText)
                }
                .padding(.top, ExperienceSpacing.lg)

                if viewModel.didSucceed {
                    successCard
                } else {
                    AuthTextField(
                        title: "Email",
                        text: $viewModel.email,
                        kind: .email,
                        textContentType: .username,
                        submitLabel: .send,
                        onSubmit: {
                            Task { await viewModel.submit() }
                        }
                    )

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .experienceStyle(.footnote, color: colors.error)
                    }

                    ExperienceButton(
                        title: "Send Reset Link",
                        kind: .primary,
                        isEnabled: viewModel.canSubmit,
                        isLoading: viewModel.isSubmitting,
                        accessibilityIdentifier: "auth.reset.submit"
                    ) {
                        Task { await viewModel.submit() }
                    }
                }
            }
            .experiencePadding(.xl)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .experienceScreenBackground()
        .navigationTitle("Reset Password")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var successCard: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            Label {
                Text("Check your inbox")
                    .experienceStyle(.headline, color: colors.primaryText)
            } icon: {
                Image(systemName: "envelope.open.fill")
                    .foregroundStyle(colors.accent)
            }
            Text("If an account exists for that email, a reset link is on the way.")
                .experienceStyle(.body, color: colors.secondaryText)
            ExperienceButton(
                title: "Back to Sign In",
                kind: .primary,
                accessibilityIdentifier: "auth.reset.back"
            ) {
                dismiss()
            }
        }
        .experiencePadding(.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                .stroke(colors.border, lineWidth: ExperienceBorder.thin)
        }
    }
}
