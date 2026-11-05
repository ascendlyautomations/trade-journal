import SwiftUI

/// Visual collapsible category panel on the scorecard breakdown screen.
struct TradingScorecardCategorySection: View {
    let category: ScorecardCategoryResult
    var psychologyCards: [PsychologyInsightCard] = []

    @Environment(\.themeColors) private var colors
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: ExperienceSpacing.sm) {
                    categoryIcon
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.title)
                            .experienceStyle(.subheadline, color: colors.primaryText)
                            .fontWeight(.semibold)
                        Text(compactSubtitle)
                            .experienceStyle(.caption2, color: colors.tertiaryText)
                    }
                    Spacer(minLength: 0)
                    trailingBadge
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(colors.tertiaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                expandedContent
                    .padding(.top, ExperienceSpacing.md)
            }
        }
        .padding(ExperienceSpacing.md)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous))
        .padding(.horizontal, ExperienceSpacing.md)
        .accessibilityIdentifier("scorecard.detail.\(category.id.rawValue)")
    }

    private var categoryIcon: some View {
        let name: String = switch category.id {
        case .consistency: "arrow.triangle.2.circlepath"
        case .discipline: "checkmark.seal"
        case .risk: "shield.lefthalf.filled"
        case .psychology: "brain.head.profile"
        }
        return Image(systemName: name)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(colors.accent)
            .frame(width: 32, height: 32)
            .background(colors.accentMuted, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var compactSubtitle: String {
        "\(ScorecardVisualSupport.categoryValueLabel(category)) · \(category.coveragePercent)% cov · \(category.reliability.label)"
    }

    @ViewBuilder
    private var trailingBadge: some View {
        if let score = category.score {
            Text("\(score)")
                .font(.system(.callout, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(colors.primaryText)
        } else {
            Text(ScorecardDisplayStrings.categoryPhase1RowLabel(category: category))
                .experienceStyle(.caption2, color: colors.secondaryText)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .frame(maxWidth: 88, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        ScorecardCategoryBarRow(
            title: category.title,
            valueLabel: ScorecardVisualSupport.categoryValueLabel(category),
            fillFraction: ScorecardVisualSupport.categoryBarFillFraction(category),
            tint: category.score != nil ? colors.accent : colors.accentMuted,
            representsScore: category.score != nil
        )

        let coverageRows = ScorecardVisualSupport.coverageRows(from: category)
        if !coverageRows.isEmpty {
            ScorecardCoverageBarsView(rows: coverageRows)
                .padding(.top, ExperienceSpacing.sm)
        }

        let tiles = ScorecardVisualSupport.metricTiles(from: category)
        if !tiles.isEmpty {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: ExperienceSpacing.sm),
                    GridItem(.flexible(), spacing: ExperienceSpacing.sm),
                ],
                spacing: ExperienceSpacing.sm
            ) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                    ScorecardMetricTile(label: tile.label, value: tile.value, footnote: tile.footnote)
                }
            }
            .padding(.top, ExperienceSpacing.sm)
        }

        if category.id == .psychology {
            psychologyInsightsBlock
        }

        if !category.dataGaps.isEmpty {
            insufficientDataBanner
        }
    }

    @ViewBuilder
    private var psychologyInsightsBlock: some View {
        if psychologyCards.isEmpty {
            Text("Complete a check-in on a day you trade to unlock insight cards.")
                .experienceStyle(.caption, color: colors.tertiaryText)
                .padding(.top, ExperienceSpacing.sm)
        } else {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                Text("Insights")
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .padding(.top, ExperienceSpacing.sm)
                ForEach(psychologyCards.prefix(4), id: \.id) { card in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.displayHeadline)
                            .experienceStyle(.footnote, color: colors.primaryText)
                            .fontWeight(.medium)
                            .lineLimit(2)
                        Text(card.displayDetail)
                            .experienceStyle(.caption2, color: colors.secondaryText)
                            .lineLimit(3)
                    }
                    .padding(ExperienceSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(colors.fillSecondary.opacity(0.35), in: RoundedRectangle(
                        cornerRadius: ExperienceRadius.sm,
                        style: .continuous
                    ))
                }
            }
        }
    }

    private var insufficientDataBanner: some View {
        HStack(spacing: ExperienceSpacing.xs) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
            Text(
                GeneratedProseNormalizer.normalize(
                    category.dataGaps.first ?? "More data needed to score."
                )
            )
                .experienceStyle(.caption2, color: colors.secondaryText)
                .lineLimit(2)
        }
        .padding(ExperienceSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous))
        .padding(.top, ExperienceSpacing.sm)
    }
}
