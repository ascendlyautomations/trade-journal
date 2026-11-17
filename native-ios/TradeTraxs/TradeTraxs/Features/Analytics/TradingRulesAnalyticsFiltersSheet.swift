import SwiftUI

struct TradingRulesAnalyticsFiltersSheet: View {
    @Bindable var scope: TradingRulesAnalyticsScopeController
    @Environment(\.themeColors) private var colors
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                    VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                            Text("ACCOUNT TYPE")
                                .font(ExperienceTypography.caption.weight(.semibold))
                                .foregroundStyle(colors.secondaryText)
                            Picker("Account Type", selection: $scope.draftScopeFilters.accountType) {
                                ForEach(DashboardScopeFilterSupport.dashboardAccountTypeCases) { mode in
                                    Text(DashboardScopeFilterSupport.accountTypeTitle(mode)).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                            Text("VISIBILITY")
                                .font(ExperienceTypography.caption.weight(.semibold))
                                .foregroundStyle(colors.secondaryText)
                            Picker("Visibility", selection: $scope.draftScopeFilters.visibility) {
                                ForEach(DashboardTradeVisibilityFilter.allCases) { value in
                                    Text(value.title).tag(value)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    .padding(ExperienceSpacing.md)
                    .experienceTradingRulesCard(prominence: .standard)
                }
                .padding(ExperienceSpacing.md)
            }
            .background(colors.backgroundPrimary.ignoresSafeArea())
            .experienceNavigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        scope.applyAdvancedFiltersFromDraft()
                        dismiss()
                    }
                }
            }
        }
        .accessibilityIdentifier("tradingRulesAnalytics.filtersSheet")
    }
}