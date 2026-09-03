import SwiftUI

/// Subtle pre-trade psychology context from today's check-in — non-blocking.
struct AddTradePreTradePsychologyNotice: View {
    let focusLevel: Int?
    let message: String?

    @Environment(\.themeColors) private var colors

    var body: some View {
        if let focusLevel, let message {
            VStack(alignment: .leading, spacing: 4) {
                Text("Focus today: \(focusLevel)/5")
                    .experienceStyle(.caption, color: colors.tertiaryText)
                Text(message)
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }
            .padding(ExperienceSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.surfaceSecondary, in: RoundedRectangle(cornerRadius: ExperienceRadius.sm))
            .accessibilityIdentifier("addTrade.preTradePsychologyNotice")
        }
    }
}

enum AddTradePreTradePsychologyPolicy {
    static func noticeMessage(facts: PsychologyCoachFacts?, focusLevel: Int?) -> String? {
        guard let focusLevel, focusLevel <= 2 else { return nil }
        guard let facts else { return nil }
        let hasFocusPattern = facts.topInsights.contains {
            $0.category == "mentalState" && $0.headline.localizedCaseInsensitiveContains("focus")
        }
        guard hasFocusPattern else { return nil }
        return "Your historical expectancy is lower on low-focus days."
    }
}
