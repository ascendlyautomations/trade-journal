import SwiftUI

/// Recoverable surface when onboarding gate resolution fails (network / server).
struct ProfileOnboardingResolveView: View {
    enum Presentation: Sendable {
        case connectivity
        case generic
    }

    let message: String
    let isRetrying: Bool
    var presentation: Presentation = .generic
    let onRetry: () -> Void
    let onSignOut: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(spacing: ExperienceSpacing.xl) {
            Spacer(minLength: ExperienceSpacing.xxl)

            ExperienceIcon(icon: .offline, size: .xl, color: colors.secondaryText)
                .accessibilityHidden(true)

            VStack(spacing: ExperienceSpacing.sm) {
                Text(title)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .foregroundStyle(colors.primaryText)
                    .multilineTextAlignment(.center)

                Text(subtitle)
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

                if presentation == .generic {
                    Button(action: onSignOut) {
                        Text("Sign Out")
                            .experienceStyle(.body, color: colors.accent)
                    }
                    .accessibilityIdentifier("onboarding.resolve.signOut")
                } else {
                    Button(action: onSignOut) {
                        Text("Sign out")
                            .experienceStyle(.caption, color: colors.tertiaryText)
                    }
                    .accessibilityIdentifier("onboarding.resolve.signOut")
                }
            }
            .padding(.horizontal, ExperienceSpacing.xl)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .experienceScreenBackground()
        .accessibilityIdentifier("onboarding.resolve.root")
    }

    private var title: String {
        switch presentation {
        case .connectivity:
            return "You're offline"
        case .generic:
            return "Couldn't load your profile setup"
        }
    }

    private var subtitle: String {
        switch presentation {
        case .connectivity:
            return "Your session is still signed in. We'll retry automatically when you're back online."
        case .generic:
            return message
        }
    }
}
