import SwiftUI

/// Compact confirmation after every Getting Started task is complete.
struct GettingStartedCompletionSheet: View {
    let onContinue: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(spacing: ExperienceSpacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(colors.profit)
                .accessibilityHidden(true)

            Text("You're All Set!")
                .experienceStyle(.title3, color: colors.primaryText)
                .multilineTextAlignment(.center)

            Text("You've completed Getting Started.\nEnjoy TradeTraxs!")
                .experienceStyle(.callout, color: colors.secondaryText)
                .multilineTextAlignment(.center)

            ExperienceButton(
                title: "Continue",
                accessibilityIdentifier: "gettingStarted.completion.continue",
                action: onContinue
            )
            .padding(.top, ExperienceSpacing.xs)
        }
        .padding(.horizontal, ExperienceSpacing.lg)
        .padding(.top, ExperienceSpacing.xl)
        .padding(.bottom, ExperienceSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(colors.cardBackground)
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
        .presentationBackground(colors.cardBackground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gettingStarted.completion")
    }
}
