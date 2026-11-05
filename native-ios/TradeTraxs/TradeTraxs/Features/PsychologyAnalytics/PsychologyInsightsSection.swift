import SwiftUI

struct PsychologyInsightsSection: View {
    let title: String
    var subtitle: String? = nil
    let cards: [PsychologyInsightCard]
    var unlockProgress: PsychologyInsightsUnlockProgress = .zero
    var unlockMetricsReady: Bool = true
    var hasMatchedCheckInDays: Bool = false
    var postUnlockGapMessages: [String] = []
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
                    if !unlockMetricsReady {
                        loadingState
                    } else if !hasMatchedCheckInDays {
                        noMatchedDaysEmptyState
                    } else if !unlockProgress.showsRequirementMessage {
                        postUnlockGapState
                    } else {
                        noMatchedDaysEmptyState
                    }
                } else {
                    if unlockProgress.showsRequirementMessage {
                        unlockProgressCaption
                    }
                    VStack(spacing: ExperienceSpacing.xs) {
                        ForEach(visibleCards) { card in
                            Button {
                                ExperienceHaptics.play(.selection)
                                onSelect(card)
                            } label: {
                                psychologyCard(card)
                            }
                            .buttonStyle(.experiencePlain)
                        }
                        if showsViewMore {
                            DashboardInsightViewMoreControl(
                                isExpanded: showsAllCards,
                                collapsedTitle: "Show \(cards.count - DashboardInsightPresentation.previewCount) more insights"
                            ) {
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

    private var loadingState: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            ProgressView()
            Text("Loading psychology insights…")
                .experienceStyle(.footnote, color: colors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.bottom, ExperienceSpacing.xs)
        .accessibilityIdentifier("dashboard.psychologyInsights.loading")
    }

    private var postUnlockGapState: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Overview unlocked")
                .experienceStyle(.subheadline, color: colors.primaryText)
                .fontWeight(.semibold)
            Text(
                "Your analytics overview is unlocked. Comparison cards appear when groups have enough matched, tagged trades."
            )
            .experienceStyle(.caption, color: colors.secondaryText)
            if postUnlockGapMessages.isEmpty {
                Text(PsychologyProgressMessaging.unlockOverviewCopy)
                    .experienceStyle(.caption, color: colors.secondaryText)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(postUnlockGapMessages, id: \.self) { message in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                            Text(GeneratedProseNormalizer.normalize(message))
                                .experienceStyle(.caption, color: colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfacePrimary, in: RoundedRectangle(cornerRadius: ExperienceRadius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                .stroke(colors.border, lineWidth: 1)
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.bottom, ExperienceSpacing.xs)
        .accessibilityIdentifier("dashboard.psychologyInsights.gaps")
    }

    private var noMatchedDaysEmptyState: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("No matched days yet")
                .experienceStyle(.subheadline, color: colors.primaryText)
                .fontWeight(.semibold)
            Text(
                "Log a daily check-in on the same Eastern calendar day as a trade in this filter scope to see sleep, mood, and performance relationships."
            )
            .experienceStyle(.caption, color: colors.secondaryText)
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfacePrimary, in: RoundedRectangle(cornerRadius: ExperienceRadius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                .stroke(colors.border, lineWidth: 1)
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.bottom, ExperienceSpacing.xs)
        .accessibilityIdentifier("dashboard.psychologyInsights.empty")
    }

    private var unlockProgressCaption: some View {
        Text(
            "Full analytics depth: check-in days \(unlockProgress.displayCheckInDayCountForGate)/\(PsychologyInsightsUnlockProgress.requiredCount) · trades \(unlockProgress.displayTradeCountForGate)/\(PsychologyInsightsUnlockProgress.requiredCount)"
        )
        .experienceStyle(.caption2, color: colors.tertiaryText)
        .monospacedDigit()
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.bottom, ExperienceSpacing.xs)
        .accessibilityIdentifier("dashboard.psychologyInsights.progress")
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
                Text(card.displayHeadline)
                    .experienceStyle(.footnote, color: colors.primaryText)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.leading)
                Text(card.displayDetail)
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .lineLimit(2)
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
        .experienceDashboardCard(prominence: .standard)
        .overlay {
            RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                .stroke(colors.accent.opacity(0.28), lineWidth: ExperienceBorder.hairline)
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
