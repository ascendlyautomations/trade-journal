import SwiftUI

/// Recoverable surface when session validation/refresh fails transiently (offline, timeout, 5xx).
struct SessionValidationView: View {
    let message: String
    let isRetrying: Bool
    let onRetry: () -> Void
    let onSignIn: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(spacing: ExperienceSpacing.xl) {
            Spacer(minLength: ExperienceSpacing.xxl)

            ExperienceIcon(icon: .offline, size: .xl, color: colors.secondaryText)
                .accessibilityHidden(true)

            VStack(spacing: ExperienceSpacing.sm) {
                Text("Couldn't restore your session")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .foregroundStyle(colors.primaryText)
                    .multilineTextAlignment(.center)

                Text(message)
                    .experienceStyle(.body, color: colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, ExperienceSpacing.xl)

            VStack(spacing: ExperienceSpacing.md) {
                ExperienceButton(
                    title: isRetrying ? "Retrying…" : "Try Again",
                    kind: .primary,
                    isLoading: isRetrying,
                    action: onRetry
                )
                .disabled(isRetrying)
                .accessibilityIdentifier("auth.validation.retry")

                Button {
                    onSignIn()
                } label: {
                    Text("Sign In")
                        .experienceStyle(.body, color: colors.accent)
                }
                .accessibilityIdentifier("auth.validation.signIn")
            }
            .padding(.horizontal, ExperienceSpacing.xl)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .experienceScreenBackground()
        .accessibilityIdentifier("auth.validation.root")
    }
}
