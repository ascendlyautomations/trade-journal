import SwiftUI

/// Compact trading-rules adherence for the Home dashboard.
struct DashboardTradingRulesComplianceSection: View {
    @Bindable private var session = TradingRulesComplianceSessionStore.shared
    var compliancePresentation: ProPremiumFeaturePresentation = .unrestricted
    var onOpenDetail: () -> Void
    var onOpenSettings: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        switch compliancePresentation {
        case .verifyingEntitlement:
            EmptyView()
        case .unrestricted, .lockedPreview:
            complianceSection
        }
    }

    private var complianceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader

            Group {
                if !session.ready {
                    loadingPlaceholder
                } else if !session.hasConfiguredRules {
                    setupCard
                } else if session.insufficientScope {
                    filteredEmptyCard
                } else if let result = session.result {
                    card(result: result)
                } else {
                    emptyCard
                }
            }
            .padding(.horizontal, ExperienceSpacing.md)
        }
        .accessibilityIdentifier("dashboard.tradingRulesCompliance")
    }

    private var sectionHeader: some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.xxs) {
            Text("Trading Rules")
                .experienceStyle(.headline, color: colors.primaryText)
                .accessibilityAddTraits(.isHeader)
            AnalyticsMetricInfoButton(
                title: "Trading Rules",
                bodyText: "Compliance is the share of evaluated rule checks that were followed in this filter. Violations broke a configured rule. Unevaluated checks are missing the fields those rules need.",
                accessibilityID: "dashboard.sectionInfo.trading-rules"
            )
            Spacer(minLength: 0)
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.bottom, ExperienceSpacing.md)
    }

    private func card(result: TradingRulesComplianceAnalytics.Result) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Compliance")
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                    Text(
                        result.score.adherencePercent.map { "\($0, specifier: "%.1f")%" } ?? "—"
                    )
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(colors.primaryText)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Followed")
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                    Text("\(result.score.followed)")
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(colors.profit)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Violations")
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                    Text("\(result.score.violated)")
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(result.score.violated > 0 ? colors.loss : colors.secondaryText)
                }

                Spacer(minLength: 0)
            }

            if session.isProvisionalCompliance {
                Text("Preliminary — full trade history is still loading. Numbers may change.")
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                    .accessibilityIdentifier("dashboard.tradingRulesCompliance.provisional")
            }

            scopeAndAnalyticsRow
        }
        .padding(ExperienceSpacing.md)
        .experienceDashboardCard(prominence: .featured)
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Configure personal rules to track adherence, violations, and impact.")
                .experienceStyle(.caption, color: colors.secondaryText)
            Button("Set Up Rules", action: onOpenSettings)
                .font(.subheadline.weight(.semibold))
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceDashboardCard(prominence: .featured)
    }

    private var loadingPlaceholder: some View {
        ExperienceSkeleton(height: 100, cornerRadius: ExperienceRadius.lg)
    }

    private var filteredEmptyCard: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("No trades in the current dashboard filter. Adjust filters or open View Analytics for details.")
                .experienceStyle(.caption, color: colors.secondaryText)
            viewAnalyticsFooter
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceDashboardCard(prominence: .featured)
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text("Log trades in this scope to measure rule compliance.")
                .experienceStyle(.caption, color: colors.secondaryText)
            viewAnalyticsFooter
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceDashboardCard(prominence: .featured)
    }

    private var scopeAndAnalyticsRow: some View {
        HStack(spacing: ExperienceSpacing.xs) {
            if !session.scopeLabel.isEmpty {
                Text(session.scopeLabel)
                    .experienceStyle(.caption2, color: colors.tertiaryText)
            }
            Spacer(minLength: 0)
            viewAnalyticsButton
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var viewAnalyticsButton: some View {
        Button {
            ExperienceHaptics.play(.selection)
            onOpenDetail()
        } label: {
            HStack(spacing: 4) {
                Text("View Analytics")
                    .experienceStyle(.caption, color: colors.accent)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(colors.accent)
            }
            .frame(minHeight: 28)
        }
        .buttonStyle(.experiencePlain)
        .accessibilityLabel("View Trading Rules Analytics")
        .accessibilityIdentifier("dashboard.tradingRules.viewAnalytics")
    }

    @ViewBuilder
    private var viewAnalyticsFooter: some View {
        if session.ready && session.hasConfiguredRules {
            HStack {
                Spacer(minLength: 0)
                viewAnalyticsButton
            }
        }
    }
}