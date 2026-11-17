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
                    adherencePanel(result: result)
                    if !result.insights.isEmpty {
                        insightsPanel(result: result)
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
            }

            if result.overall.score == nil {
                Text(result.overall.statusMessage)
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .multilineTextAlignment(.center)
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

    private func adherencePanel(result: ScorecardResult) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            ForEach(result.adherence) { row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.label)
                        .experienceStyle(.subheadline, color: colors.secondaryText)
                    Spacer(minLength: 8)
                    Text(row.value ?? row.pending ?? "")
                        .experienceStyle(.subheadline, color: colors.primaryText)
                        .fontWeight(.semibold)
                }
                if let sample = row.sample {
                    Text(sample)
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                }
            }
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous))
        .padding(.horizontal, ExperienceSpacing.md)
    }

    private func insightsPanel(result: ScorecardResult) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Insights")
                .experienceStyle(.headline, color: colors.primaryText)
            ForEach(result.insights) { insight in
                Text(insight.text)
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous))
        .padding(.horizontal, ExperienceSpacing.md)
    }

    private func refreshEntitlementGate() {
        let profileID = SessionBootstrapStore.shared.last.map { ProfileID($0.data.viewer.id) }
        restrictsPremiumPsychology = ProMonetizationPolicy.shouldRestrictPremiumPsychologyAndAI(
            demoModeActive: ExploreModeSupport.isActive,
            profileID: profileID
        )
    }
}
