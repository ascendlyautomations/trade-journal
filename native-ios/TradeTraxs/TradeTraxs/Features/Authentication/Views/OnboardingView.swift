import SwiftUI

struct OnboardingView: View {
    let navigationCoordinator: NavigationCoordinator

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: ExperienceSpacing.xxl)

            VStack(spacing: ExperienceSpacing.xl) {
                ZStack {
                    Circle()
                        .fill(colors.accent.opacity(0.14))
                        .frame(width: 120, height: 120)
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(colors.accent)
                }
                .scaleEffect(appeared ? 1 : 0.9)
                .accessibilityHidden(true)

                VStack(spacing: ExperienceSpacing.sm) {
                    Text("Journal every trade.\nImprove every session.")
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .foregroundStyle(colors.primaryText)
                        .multilineTextAlignment(.center)

                    Text("Track performance, share wins, and stay consistent — built natively for iPhone.")
                        .experienceStyle(.body, color: colors.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, ExperienceSpacing.xl)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
            }

            Spacer()

            VStack(spacing: ExperienceSpacing.sm) {
                ExperienceButton(
                    title: "Get Started",
                    kind: .primary,
                    accessibilityIdentifier: "auth.onboarding.getStarted"
                ) {
                    navigationCoordinator.open(.auth(.login))
                }

                ExperienceButton(
                    title: "I already have an account",
                    kind: .secondary,
                    accessibilityIdentifier: "auth.onboarding.signIn"
                ) {
                    navigationCoordinator.open(.auth(.login))
                }
            }
            .experiencePadding(.xl)
            .padding(.bottom, ExperienceSpacing.xxl)
        }
        .experienceScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            ExperienceMotion.withAnimation(
                ExperienceMotion.navigation,
                reduceMotion: reduceMotion
            ) {
                appeared = true
            }
        }
    }
}

struct AuthPlanPlaceholderView: View {
    let title: String
    let message: String
    let navigationCoordinator: NavigationCoordinator

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
            Text(message)
                .experienceStyle(.body, color: colors.secondaryText)
            Spacer()
            ExperienceButton(title: "Continue", kind: .primary) {
                navigationCoordinator.open(.auth(.login))
            }
        }
        .experiencePadding(.xl)
        .experienceScreenBackground()
        .experienceNavigationTitle(title)
    }
}
