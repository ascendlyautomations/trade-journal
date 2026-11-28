import SwiftUI

/// Trade Detail entry — opens the dedicated conversation screen.
struct TradeAIEntrySectionView: View {
    let tradeID: TradeID
    let previewCount: Int
    let onOpen: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        TradeDetailGroupedSurface {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                HStack(spacing: ExperienceSpacing.xs) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(colors.accent)
                    Text("Trade AI")
                        .experienceStyle(.subheadline, color: colors.primaryText)
                        .fontWeight(.semibold)
                    Spacer()
                }

                Text(
                    previewCount > 0
                        ? "\(previewCount) messages in this trade’s AI conversation."
                        : "Get a coach review, compare to your history, and ask follow-ups."
                )
                .experienceStyle(.caption, color: colors.secondaryText)

                Button(action: onOpen) {
                    Text("Open Trade AI")
                        .font(.system(.subheadline, design: .default).weight(.semibold))
                        .foregroundStyle(colors.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            colors.accent,
                            in: RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                        )
                }
                .buttonStyle(.experiencePlain)
                .accessibilityIdentifier("detail.trade.ai.open")

                ComplianceDisclaimerFootnote(
                    text: ComplianceDisclaimerCopy.tradeAI,
                    showsTermsLink: true
                )
            }
        }
        .accessibilityIdentifier("detail.trade.ai.section")
    }
}