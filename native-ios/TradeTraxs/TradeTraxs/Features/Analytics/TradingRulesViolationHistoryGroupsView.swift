import SwiftUI

struct TradingRulesViolationHistoryGroupsView: View {
    let navigationCoordinator: NavigationCoordinator
    let detailCache: DetailPresentationCache

    @Bindable private var session: TradingRulesComplianceSessionStore
    @Environment(\.themeColors) private var colors

    init(navigationCoordinator: NavigationCoordinator, detailCache: DetailPresentationCache) {
        self.navigationCoordinator = navigationCoordinator
        self.detailCache = detailCache
        _session = Bindable(TradingRulesCompliancePresentationStores.store(detailCache: detailCache))
    }

    var body: some View {
        Group {
            if let violations = session.result?.violations {
                groupsList(violations)
            } else {
                ExperienceEmptyState(
                    icon: .chart,
                    title: "No violation history",
                    message: "Return to Trading Rules Analytics or widen your filters."
                )
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Violation history")
        .safeAreaInset(edge: .top, spacing: 0) {
            if TradingRulesAnalyticsPreviewSupport.showsSampleDataChrome {
                TradingRulesAnalyticsSampleDataBanner(compactListSubtitle: true)
            }
        }
        .accessibilityIdentifier("tradingRulesAnalytics.violationHistory")
    }

    @ViewBuilder
    private func groupsList(_ violations: [TradingRulesComplianceAnalytics.ViolationEvent]) -> some View {
        let groups = TradingRulesViolationGrouping.ruleGroups(from: violations)

        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                if !session.scopeLabel.isEmpty {
                    Text(session.scopeLabel)
                        .experienceStyle(.caption, color: colors.secondaryText)
                }

                if groups.isEmpty {
                    Text("No violations in this scope.")
                        .experienceStyle(.caption, color: colors.secondaryText)
                } else {
                    VStack(spacing: ExperienceSpacing.xs) {
                        ForEach(groups) { group in
                            ruleGroupRow(group)
                        }
                    }
                }
            }
            .padding(ExperienceSpacing.md)
        }
    }

    @ViewBuilder
    private func ruleGroupRow(_ group: TradingRulesViolationGrouping.RuleGroup) -> some View {
        Button {
            navigationCoordinator.pushTradingRulesRuleDetail(group.ruleID.rawValue)
        } label: {
            HStack(spacing: ExperienceSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.ruleLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(colors.primaryText)
                        .lineLimit(2)
                    Text("\(group.violationCount) violation\(group.violationCount == 1 ? "" : "s")")
                        .experienceStyle(.caption2, color: colors.secondaryText)
                }
                Spacer(minLength: 0)
                Text("\(group.violationCount)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(colors.loss)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(colors.tertiaryText)
            }
            .padding(ExperienceSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .experienceTradingRulesCard(prominence: .standard)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}