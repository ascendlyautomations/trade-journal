import SwiftUI

struct TradingRulesAnalyticsFilterBar: View {
    @Bindable var scope: TradingRulesAnalyticsScopeController
    var onManageAccounts: () -> Void
    var onFiltersTap: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.xs) {
            HStack(spacing: ExperienceSpacing.xs) {
                accountMenu
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(0)
                timePeriodButton
                    .layoutPriority(2)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .layoutPriority(2)

            Spacer(minLength: ExperienceSpacing.xxs)

            advancedFiltersButton
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("tradingRulesAnalytics.filterBar")
    }

    private var accountMenu: some View {
        let profileID = scope.profileID
        let title = scope.accountMenuTitle
        return OwnerAccountFilterDropdown(
            accounts: scope.accountsForMenu,
            selectedFilter: scope.accountFilter,
            copyGroups: OwnerAccountFilterMenuSupport.copyGroups(for: profileID),
            isLoadingCopyGroups: OwnerAccountFilterMenuSupport.isLoadingCopyGroups(for: profileID),
            onSelectFilter: { scope.setAccountFilter($0) },
            onManageAccounts: onManageAccounts,
            onManageCopyGroups: { scope.openManageCopyTradingGroups() },
            onRequestCopyGroups: {
                OwnerAccountFilterMenuSupport.requestCopyGroupsLoad(profileID: profileID)
            },
            accessibilityIdentifier: "tradingRulesAnalytics.account",
            boundary: .dashboard,
            profileID: profileID
        ) {
            accountMenuLabel(title)
        }
        .accessibilityLabel("Account")
        .accessibilityValue(title)
    }

    private var selectedAccountTitle: String { scope.accountMenuTitle }

    private var timePeriodButton: some View {
        Button {
            scope.openTimePeriodFilters()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "slider.horizontal.3")
                    .font(.footnote.weight(.semibold))
                Text(scope.scopeFilterTimeLabel)
                    .experienceStyle(.footnote, color: colors.primaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, ExperienceSpacing.sm)
            .frame(minHeight: 32)
            .experienceFilterCapsule()
            .overlay(alignment: .topTrailing) {
                if scope.showsTimePeriodFilterIndicator {
                    Circle()
                        .fill(colors.accent)
                        .frame(width: 7, height: 7)
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.experiencePlain)
        .accessibilityLabel("Time period")
        .accessibilityValue(scope.scopeFilterTimeLabel)
        .accessibilityIdentifier("tradingRulesAnalytics.scopeFilters")
    }

    private var advancedFiltersButton: some View {
        Button(action: onFiltersTap) {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.footnote.weight(.semibold))
                Text("Filters")
                    .experienceStyle(.footnote, color: colors.primaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, ExperienceSpacing.sm)
            .frame(minHeight: 32)
            .experienceFilterCapsule()
            .overlay(alignment: .topTrailing) {
                if scope.showsAdvancedFilterIndicator {
                    Circle()
                        .fill(colors.accent)
                        .frame(width: 7, height: 7)
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.experiencePlain)
        .accessibilityLabel("Account type and visibility filters")
        .accessibilityIdentifier("tradingRulesAnalytics.filters")
    }

    private func accountMenuLabel(_ title: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .experienceStyle(.footnote, color: colors.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            ExperienceIcon(icon: .chevronDown, size: .xs, color: colors.secondaryText)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
        .padding(.horizontal, ExperienceSpacing.sm)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .experienceFilterCapsule()
    }
}

struct TradingRulesAnalyticsTimePeriodSheet: View {
    @Bindable var scope: TradingRulesAnalyticsScopeController
    @Environment(\.themeColors) private var colors
    @Environment(\.dismiss) private var dismiss

    private let sectionSpacing = ExperienceSpacing.lg

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: sectionSpacing) {
                    VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                        Text("TIME PERIOD")
                            .font(ExperienceTypography.caption.weight(.semibold))
                            .foregroundStyle(colors.secondaryText)
                        DashboardScopeTimePeriodFields(draft: $scope.draftScopeFilters)
                    }
                }
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.vertical, ExperienceSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(colors.backgroundPrimary.ignoresSafeArea())
            .experienceNavigationTitle("Time Period")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("tradingRulesAnalytics.timePeriod.cancel")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        scope.draftScopeFilters.timePeriod = .thirtyDays
                        scope.draftScopeFilters.customStart = nil
                        scope.draftScopeFilters.customEnd = nil
                    }
                    .accessibilityIdentifier("tradingRulesAnalytics.timePeriod.reset")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        scope.applyTimePeriodFromDraft()
                        dismiss()
                    }
                    .accessibilityIdentifier("tradingRulesAnalytics.timePeriod.apply")
                }
            }
        }
        .accessibilityIdentifier("tradingRulesAnalytics.timePeriodSheet")
    }
}