import SwiftUI

struct TradingScorecardDetailView: View {
    @Bindable private var session = TradingScorecardSessionStore.shared
    let navigationCoordinator: NavigationCoordinator
    let data: DataEnvironment

    @Environment(\.themeColors) private var colors
    @State private var restrictsPremiumPsychology = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                if let result = session.result {
                    heroPanel(result: result)
                    categoryOverviewStrip(result: result)
                    ForEach(result.categories, id: \.id) { category in
                        TradingScorecardCategorySection(
                            category: category,
                            psychologyCards: category.id == .psychology ? session.psychologyInsightCards : []
                        )
                    }
                    if !restrictsPremiumPsychology {
                        Button {
                            navigationCoordinator.pushHome(.psychologyAnalytics)
                        } label: {
                            Label("Psychology Analytics", systemImage: "chart.xyaxis.line")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(colors.accent)
                        .padding(.horizontal, ExperienceSpacing.md)
                    }
                } else {
                    Text("Return to the dashboard with trades in scope.")
                        .experienceStyle(.body, color: colors.secondaryText)
                        .padding(.horizontal, ExperienceSpacing.md)
                }
            }
            .padding(.vertical, ExperienceSpacing.lg)
        }
        .background(colors.appBackground)
        .experienceNavigationTitle("Scorecard")
        .onAppear { refreshEntitlementGate() }
    }

    private func heroPanel(result: ScorecardResult) -> some View {
        VStack(spacing: ExperienceSpacing.md) {
            Text(result.scopeLabel)
                .experienceStyle(.caption, color: colors.secondaryText)
                .multilineTextAlignment(.center)

            ScorecardScoreRingView(
                score: result.overall.status == .ready ? result.overall.score : nil,
                buildingProgress: result.overall.score == nil
                    ? ScorecardVisualSupport.buildingProgress(
                        tradeCount: result.overall.tradeCount,
                        tradingDayCount: result.overall.tradingDayCount
                    )
                    : nil,
                size: 132,
                lineWidth: 12
            )

            HStack(spacing: ExperienceSpacing.lg) {
                statPill("\(result.overall.tradeCount)", label: "Trades")
                statPill("\(result.overall.tradingDayCount)", label: "Days")
                statPill("\(result.overall.coveragePercent)%", label: "Coverage")
            }

            if !result.overall.contributions.isEmpty {
                contributionsStrip(result: result)
            } else if result.overall.score == nil {
                gateHint(result: result)
            }
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous))
        .padding(.horizontal, ExperienceSpacing.md)
        .accessibilityIdentifier("scorecard.detail")
    }

    private func statPill(_ value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.callout, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(colors.primaryText)
            Text(label)
                .experienceStyle(.caption2, color: colors.tertiaryText)
        }
    }

    private func contributionsStrip(result: ScorecardResult) -> some View {
        HStack(spacing: ExperienceSpacing.sm) {
            ForEach(result.overall.contributions, id: \.id) { row in
                VStack(spacing: 2) {
                    Text("\(row.score)")
                        .font(.system(.caption, design: .rounded).weight(.bold).monospacedDigit())
                    Text(row.title)
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                        .lineLimit(1)
                    Text("\(Int(row.effectiveWeight * 100))%")
                        .experienceStyle(.caption2, color: colors.accent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, ExperienceSpacing.xs)
                .background(colors.fillSecondary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func gateHint(result: ScorecardResult) -> some View {
        HStack(spacing: ExperienceSpacing.xs) {
            Image(systemName: "hourglass")
                .foregroundStyle(colors.tertiaryText)
            Text("\(result.overall.tradeCount)/\(ScorecardConstants.minTradesOverall) trades · \(result.overall.tradingDayCount)/\(ScorecardConstants.minTradingDaysOverall) days")
                .experienceStyle(.caption, color: colors.tertiaryText)
        }
    }

    private func categoryOverviewStrip(result: ScorecardResult) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ExperienceSpacing.sm) {
                ForEach(result.categories, id: \.id) { category in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(category.title)
                            .experienceStyle(.caption2, color: colors.tertiaryText)
                        Text(ScorecardVisualSupport.categoryValueLabel(category))
                            .font(.system(.footnote, design: .rounded).weight(.semibold).monospacedDigit())
                            .foregroundStyle(colors.primaryText)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(colors.fillSecondary)
                                Capsule()
                                    .fill(colors.accent.opacity(category.score != nil ? 0.85 : 0.35))
                                    .frame(width: geo.size.width * ScorecardVisualSupport.categoryFillFraction(category))
                            }
                        }
                        .frame(height: 4)
                    }
                    .padding(ExperienceSpacing.sm)
                    .frame(width: 108)
                    .background(colors.elevatedSurface, in: RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous))
                }
            }
            .padding(.horizontal, ExperienceSpacing.md)
        }
    }

    private func refreshEntitlementGate() {
        let profileID = SessionBootstrapStore.shared.last.map { ProfileID($0.data.viewer.id) }
        restrictsPremiumPsychology = ProMonetizationPolicy.shouldRestrictPremiumPsychologyAndAI(
            demoModeActive: ExploreModeSupport.isActive,
            profileID: profileID
        )
    }
}
