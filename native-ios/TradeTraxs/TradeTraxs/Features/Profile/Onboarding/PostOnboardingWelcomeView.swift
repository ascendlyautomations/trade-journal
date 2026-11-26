import SwiftUI

struct PostOnboardingWelcomeView: View {
    let onTakeTour: () -> Void
    let onMaybeLater: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                    HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
                        Image("AppLogo")
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous))
                            .accessibilityHidden(true)
                        Text("Welcome to TradeTraxs!")
                            .experienceStyle(.title2, color: colors.primaryText)
                            .fontWeight(.bold)
                            .accessibilityAddTraits(.isHeader)
                    }
                    Text(
                        "Your all-in-one trading platform. Journal your trades, track your performance, and connect with other traders."
                    )
                    .experienceStyle(.body, color: colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    Text(
                        "Would you like to take a quick tour? We've also prepared a few Getting Started tasks to help you get set up."
                    )
                    .experienceStyle(.body, color: colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                }

                ExperienceButton(
                    title: "Take a Tour",
                    kind: .primary,
                    accessibilityIdentifier: "postOnboarding.welcome.takeTour"
                ) {
                    ExperienceHaptics.play(.selection)
                    onTakeTour()
                }

                ExperienceButton(
                    title: "Maybe Later",
                    kind: .secondary,
                    accessibilityIdentifier: "postOnboarding.welcome.maybeLater"
                ) {
                    ExperienceHaptics.play(.selection)
                    onMaybeLater()
                }
            }
            .padding(ExperienceSpacing.xl)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .experienceScreenBackground()
        }
        .interactiveDismissDisabled(true)
        .accessibilityIdentifier("postOnboarding.welcome")
    }
}