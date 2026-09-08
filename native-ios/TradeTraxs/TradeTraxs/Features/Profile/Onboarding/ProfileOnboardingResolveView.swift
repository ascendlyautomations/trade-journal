import SwiftUI

/// Recoverable surface when onboarding gate resolution fails (network / server).
struct ProfileOnboardingResolveView: View {
    let message: String
    let isRetrying: Bool
    let onRetry: () -> Void
    let onSignOut: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(spacing: ExperienceSpacing.xl) {
            Spacer(minLength: ExperienceSpacing.xxl)

            ExperienceIcon(icon: .offline, size: .xl, color: colors.secondaryText)
                .accessibilityHidden(true)

            VStack(spacing: ExperienceSpacing.sm) {
                Text("Couldn't load your profile setup")
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
                .accessibilityIdentifier("onboarding.resolve.retry")

                Button(action: onSignOut) {
                    Text("Sign Out")
                        .experienceStyle(.body, color: colors.accent)
                }
                .accessibilityIdentifier("onboarding.resolve.signOut")
            }
            .padding(.horizontal, ExperienceSpacing.xl)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .experienceScreenBackground()
        .accessibilityIdentifier("onboarding.resolve.root")
    }
}
