import SwiftUI

struct PsychologyInsightsSection: View {
    let cards: [PsychologyInsightCard]
    var onSelect: (PsychologyInsightCard) -> Void
    var onViewAll: () -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack {
                Text("Psychology Insights")
                    .experienceStyle(.headline, color: colors.primaryText)
                Spacer()
                if !cards.isEmpty {
                    Button("See all", action: onViewAll)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(colors.accent)
                }
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .accessibilityAddTraits(.isHeader)

            if cards.isEmpty {
                emptyState
            } else {
                VStack(spacing: ExperienceSpacing.sm) {
                    ForEach(cards) { card in
                        Button {
                            ExperienceHaptics.play(.selection)
                            onSelect(card)
                        } label: {
                            psychologyCard(card)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, ExperienceSpacing.md)
            }
        }
        .accessibilityIdentifier("dashboard.psychologyInsights")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text("Not enough data yet")
                .experienceStyle(.subheadline, color: colors.primaryText)
                .fontWeight(.semibold)
            Text("Log daily check-ins and psychology on more trades to unlock personalized insights.")
                .experienceStyle(.footnote, color: colors.secondaryText)
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.fillSecondary.opacity(0.35), in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
        .padding(.horizontal, ExperienceSpacing.md)
    }

    private func psychologyCard(_ card: PsychologyInsightCard) -> some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.md) {
            ExperienceIcon(icon: icon(for: card.category), size: .md, color: colors.accent)
                .frame(width: 40, height: 40)
                .background(colors.accent.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(card.sectionTitle.uppercased())
                    .experienceStyle(.caption2, color: colors.accent)
                    .fontWeight(.semibold)
                    .tracking(0.5)
                Text(card.headline)
                    .experienceStyle(.subheadline, color: colors.primaryText)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.leading)
                Text(card.detail)
                    .experienceStyle(.callout, color: colors.secondaryText)
                    .multilineTextAlignment(.leading)
                Text("\(card.reliability.label) • \(card.sampleSize) trades")
                    .experienceStyle(.caption2, color: colors.tertiaryText)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(colors.tertiaryText)
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfacePrimary, in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                .stroke(colors.border, lineWidth: 1)
        }
        .accessibilityIdentifier("dashboard.psychologyInsight.\(card.id)")
    }

    private func icon(for category: PsychologyInsightCategory) -> AppIcon {
        switch category {
        case .sleep: return .calendar
        case .mentalState: return .chart
        case .conviction: return .trades
        case .discipline: return .checkmark
        case .emotion: return .profile
        case .afterLosses: return .chart
        case .tradeFrequency: return .trades
        case .combined: return .chart
        }
    }
}
