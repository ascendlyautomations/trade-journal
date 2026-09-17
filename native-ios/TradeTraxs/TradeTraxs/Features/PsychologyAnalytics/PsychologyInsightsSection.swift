import SwiftUI

struct PsychologyInsightsSection: View {
    let title: String
    var subtitle: String? = nil
    let cards: [PsychologyInsightCard]
    var onSelect: (PsychologyInsightCard) -> Void
    var onViewAll: () -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSectionExpanded = true
    @State private var showsAllCards = false

    private var visibleCards: [PsychologyInsightCard] {
        guard cards.count > DashboardInsightPresentation.previewCount, !showsAllCards else {
            return cards
        }
        return Array(cards.prefix(DashboardInsightPresentation.previewCount))
    }

    private var showsViewMore: Bool {
        cards.count > DashboardInsightPresentation.previewCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            DashboardCollapsibleSectionHeader(
                title: title,
                subtitle: subtitle,
                isExpanded: isSectionExpanded,
                trailing: cards.isEmpty
                    ? nil
                    : AnyView(
                        Button("See all", action: onViewAll)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(colors.accent)
                    ),
                onToggle: { isSectionExpanded.toggle() }
            )

            if isSectionExpanded {
                if cards.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: ExperienceSpacing.xs) {
                        ForEach(visibleCards) { card in
                            Button {
                                ExperienceHaptics.play(.selection)
                                onSelect(card)
                            } label: {
                                psychologyCard(card)
                            }
                            .buttonStyle(.plain)
                        }
                        if showsViewMore {
                            DashboardInsightViewMoreControl(isExpanded: showsAllCards) {
                                ExperienceHaptics.play(.selection)
                                withAnimation(
                                    ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion)
                                ) {
                                    showsAllCards.toggle()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.bottom, ExperienceSpacing.xs)
                }
            }
        }
        .accessibilityIdentifier("dashboard.psychologyInsights")
    }

    private var emptyState: some View {
        ExperienceEmptyState(
            icon: .chart,
            title: "Not enough data yet",
            message: "Log check-ins and trade psychology to unlock insights."
        )
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.bottom, ExperienceSpacing.xs)
    }

    private func psychologyCard(_ card: PsychologyInsightCard) -> some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
            ExperienceIcon(icon: icon(for: card.category), size: .sm, color: colors.accent)
                .frame(width: 32, height: 32)
                .background(colors.accent.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(card.sectionTitle.uppercased())
                    .experienceStyle(.caption2, color: colors.accent)
                    .fontWeight(.semibold)
                    .tracking(0.4)
                Text(card.headline)
                    .experienceStyle(.footnote, color: colors.primaryText)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.leading)
                Text(card.detail)
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .multilineTextAlignment(.leading)
                Text("\(card.reliability.label) • \(card.sampleSize) trades")
                    .experienceStyle(.caption2, color: colors.tertiaryText)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(colors.tertiaryText)
        }
        .padding(ExperienceSpacing.sm)
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
