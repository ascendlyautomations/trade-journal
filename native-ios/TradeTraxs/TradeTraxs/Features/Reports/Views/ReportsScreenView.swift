import SwiftUI

/// Reports catalog — Performance Reports + Psychology Reports.
struct ReportsScreenView: View {
    @State private var viewModel: ReportsScreenViewModel
    @State private var isPerformanceExpanded = true
    @State private var isPsychologyExpanded = true
    @State private var isPerformanceListExpanded = false
    @State private var isPsychologyListExpanded = false

    private static let compactReportCount = 2
    private static let reportsIntroDescription =
        "Performance reviews and psychology insights from your journal."
    @State private var entitlementGateRevision = 0
    private let tradingPreferences: (any TradingPreferencesRepository)?
    private let navigationCoordinator: NavigationCoordinator?
    private let data: DataEnvironment?
    private let embeddedInTraxsProPreview: Bool

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator,
        embeddedInTraxsProPreview: Bool = false
    ) {
        _viewModel = State(
            initialValue: ReportsScreenViewModel(
                tradingReports: data.tradingReports,
                psychologyReports: data.psychologyReports,
                navigationCoordinator: navigationCoordinator,
                trades: data.trades,
                session: data.session,
                detailCache: data.detailCache
            )
        )
        tradingPreferences = data.tradingPreferences
        self.navigationCoordinator = navigationCoordinator
        self.data = data
        self.embeddedInTraxsProPreview = embeddedInTraxsProPreview
    }

    init(viewModel: ReportsScreenViewModel) {
        _viewModel = State(initialValue: viewModel)
        tradingPreferences = nil
        navigationCoordinator = nil
        data = nil
        embeddedInTraxsProPreview = false
    }

    var body: some View {
        Group {
            if showsEntitlementVerification, let data {
                TraxProEntitlementVerificationView(profileID: reportsViewerProfileID) {
                    Task { await TraxProEntitlementRefreshAction.refresh(data: data) }
                }
            } else if restrictsTradingReportsCatalog {
                catalogScroll
            } else {
                switch viewModel.phase {
                case .failed(let message) where viewModel.cards.allSatisfy({ $0.availability != .ready })
                    && viewModel.psychologyCards.allSatisfy({ $0.availability != .ready }):
                    ExperienceErrorState(
                        title: "Couldn't load Reports",
                        message: message,
                        onRetry: { Task { await viewModel.refresh() } }
                    )
                default:
                    catalogScroll
                }
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Reports")
        .toolbar(.hidden, for: .tabBar)
        .refreshable {
            guard !restrictsTradingReportsCatalog else { return }
            await viewModel.refresh()
        }
        .task(id: restrictsTradingReportsCatalog) {
            guard !restrictsTradingReportsCatalog, !showsEntitlementVerification else { return }
            await viewModel.bootstrapIfNeeded()
        }
        .task(id: showsEntitlementVerification) {
            if showsEntitlementVerification, let data {
                await TraxProEntitlementRefreshAction.refresh(data: data)
            }
        }
        .sheet(isPresented: $viewModel.showsPeriodPicker) {
            PsychologyReportPeriodPickerView(
                periods: viewModel.periodPickerPeriods,
                onSelect: { viewModel.openPsychologyPeriod($0) },
                onClose: { viewModel.showsPeriodPicker = false }
            )
            .experienceSheetChrome()
        }
        .sheet(isPresented: $viewModel.showsYearPicker) {
            TradingReportYearPickerView(
                years: viewModel.availableYears,
                onSelect: { viewModel.openYearlyReport(year: $0) },
                onClose: { viewModel.showsYearPicker = false }
            )
            .experienceSheetChrome()
        }
        .sheet(isPresented: $viewModel.showsCustomRangeSheet) {
            TradingReportCustomRangeSheet(viewModel: viewModel)
                .experienceSheetChrome()
        }
        .accessibilityIdentifier("reports.home")
        .onReceive(NotificationCenter.default.publisher(for: .billingEntitlementsDidRefresh)) { _ in
            entitlementGateRevision += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .monetizationConfigurationDidChange)) { _ in
            entitlementGateRevision += 1
        }
        .onAppear {
            viewModel.syncFiltersFromSession()
        }
    }

    private var showsEntitlementVerification: Bool {
        _ = entitlementGateRevision
        return ProMonetizationPolicy.shouldShowEntitlementVerification(
            demoModeActive: ExploreModeSupport.isActive,
            profileID: reportsViewerProfileID
        )
    }

    private var restrictsTradingReportsCatalog: Bool {
        _ = entitlementGateRevision
        return ProMonetizationPolicy.shouldRestrictTradingReportsCatalog(
            demoModeActive: ExploreModeSupport.isActive,
            profileID: reportsViewerProfileID
        )
    }

    private var reportsViewerProfileID: ProfileID? {
        guard let bootstrap = SessionBootstrapStore.shared.last else { return nil }
        return ProfileID(bootstrap.data.viewer.id)
    }

    private var catalogScroll: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                intro
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.top, ExperienceSpacing.sm)

                if restrictsTradingReportsCatalog {
                    tradingReportsUpgradeBlock
                        .padding(.horizontal, ExperienceSpacing.md)
                } else {
                    performanceSection
                    psychologySection
                }
            }
            .padding(.bottom, ExperienceSpacing.xxxl)
            .animation(
                ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
                value: isPerformanceExpanded
            )
            .animation(
                ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
                value: isPsychologyExpanded
            )
            .animation(
                ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
                value: viewModel.cards.map(\.actionTitle)
            )
            .animation(
                ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
                value: isPerformanceListExpanded
            )
            .animation(
                ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
                value: isPsychologyListExpanded
            )
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.xxs) {
                    Text("Your Reports")
                        .experienceStyle(.title3, color: colors.primaryText)
                    AnalyticsMetricInfoButton(
                        title: "Your Reports",
                        bodyText: Self.reportsIntroDescription,
                        accessibilityID: "reports.intro.info"
                    )
                }
                .layoutPriority(1)

                Spacer(minLength: ExperienceSpacing.xs)

                accountFilterMenu
                    .layoutPriority(0)
            }

            if let navigationCoordinator, !embeddedInTraxsProPreview {
                ReportsConfigureTradingRulesPrompt(
                    userID: reportsViewerProfileID,
                    repository: tradingPreferences,
                    navigationCoordinator: navigationCoordinator
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accountFilterMenu: some View {
        OwnerAccountFilterDropdown(
            accounts: viewModel.accountsForMenu,
            isAllAccountsSelected: {
                if case .all = viewModel.filters.accountFilter { return true }
                return false
            }(),
            selectedAccountID: {
                if case .account(let id) = viewModel.filters.accountFilter { return id }
                return nil
            }(),
            onSelectAll: { viewModel.setAccountFilter(.all) },
            onSelectAccount: { viewModel.setAccountFilter(.account($0)) },
            onManageAccounts: { viewModel.openManageAccounts() },
            accessibilityIdentifier: "reports.home.account",
            profileID: viewModel.profileID,
            detailCache: data?.detailCache
        ) {
            HStack(spacing: 4) {
                Text(viewModel.accountFilterTitle)
                    .experienceStyle(.footnote, color: colors.accent)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: compactAccountSelectorWidth, alignment: .trailing)
                ExperienceIcon(icon: .chevronDown, size: .xs, color: colors.accent)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityLabel("Account")
        .accessibilityValue(viewModel.accountFilterTitle)
    }

    private var compactAccountSelectorWidth: CGFloat {
        let sample = String(repeating: "M", count: CalendarPresentation.compactAccountSelectorMaxLength)
        let font = UIFont.preferredFont(forTextStyle: .footnote)
        return (sample as NSString).size(withAttributes: [.font: font]).width + 2
    }

    private var tradingReportsUpgradeBlock: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("TraxsPro reports")
                .experienceStyle(.headline, color: colors.primaryText)
            Text("Performance and psychology report reviews are included with TraxsPro.")
                .experienceStyle(.footnote, color: colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: ExperienceSpacing.sm) {
                Button {
                    ExperienceHaptics.play(.selection)
                    TraxsProPreviewCoordinator.shared.presentReportsPreview(entryPoint: .reportsGate)
                } label: {
                    Text(MonetizationPlanCopy.previewWithSampleDataButtonTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("reports.preview.traxpro")

                if canPresentPaywall {
                    Button {
                        ExperienceHaptics.play(.selection)
                        ProUpgradeCoordinator.shared.present(reason: .feature(.tradingReports))
                    } label: {
                        Text(MonetizationPlanCopy.paywallUnlockTitle)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("reports.upgrade.traxpro")
                }
            }
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.fillSecondary.opacity(0.35), in: RoundedRectangle(
            cornerRadius: ExperienceRadius.md,
            style: .continuous
        ))
        .accessibilityIdentifier("reports.traxpro.gate")
    }

    private var canPresentPaywall: Bool {
        ProMonetizationPolicy.canPresentProPaywall(
            demoModeActive: ExploreModeSupport.isActive,
            enforcement: IosSubscriptionReleaseConfiguration.entitlementEnforcementEnabled,
            paywallEnabled: IosSubscriptionReleaseConfiguration.iosPaywallEnabled
        )
    }

    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            ReportsSectionHeader(
                title: "Performance Reports",
                subtitle: "Trading performance and account reports",
                isExpanded: isPerformanceExpanded,
                onToggle: { togglePerformanceSection() }
            )
            .accessibilityIdentifier("reports.section.performance")

            if isPerformanceExpanded {
                VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                    ForEach(visiblePerformanceRows) { row in
                        switch row {
                        case .period(let card):
                            performanceCard(card)
                        case .yearly(let card):
                            yearlyCardView(card)
                        case .custom:
                            customReportCard
                        }
                    }
                    .padding(.horizontal, ExperienceSpacing.md)
                    .transition(.opacity.combined(with: .move(edge: .top)))

                    reportsListExpandButton(
                        isExpanded: isPerformanceListExpanded,
                        hasMore: performanceRows.count > Self.compactReportCount,
                        accessibilityID: "reports.section.performance.showMore",
                        action: { togglePerformanceListExpanded() }
                    )
                    .padding(.horizontal, ExperienceSpacing.md)
                }
            }
        }
    }

    private var psychologySection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            ReportsSectionHeader(
                title: "Psychology Reports",
                subtitle: "Behavior, discipline and psychology reports",
                isExpanded: isPsychologyExpanded,
                onToggle: { togglePsychologySection() }
            )
            .accessibilityIdentifier("reports.section.psychology")

            if isPsychologyExpanded {
                VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                    ForEach(visiblePsychologyCards) { card in
                        psychologyCard(card)
                            .padding(.horizontal, ExperienceSpacing.md)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    reportsListExpandButton(
                        isExpanded: isPsychologyListExpanded,
                        hasMore: viewModel.psychologyCards.count > Self.compactReportCount,
                        accessibilityID: "reports.section.psychology.showMore",
                        action: { togglePsychologyListExpanded() }
                    )
                    .padding(.horizontal, ExperienceSpacing.md)
                }
            }
        }
    }

    private var performanceRows: [ReportsCatalogPerformanceRow] {
        var rows = viewModel.cards.map { ReportsCatalogPerformanceRow.period($0) }
        if let yearly = viewModel.yearlyCard {
            rows.append(.yearly(yearly))
        }
        rows.append(.custom)
        return rows
    }

    private var visiblePerformanceRows: [ReportsCatalogPerformanceRow] {
        ReportsCatalogListVisibility.visibleItems(
            from: performanceRows,
            listExpanded: isPerformanceListExpanded,
            compactCount: Self.compactReportCount
        )
    }

    private var visiblePsychologyCards: [PsychologyReportCardModel] {
        ReportsCatalogListVisibility.visibleItems(
            from: viewModel.psychologyCards,
            listExpanded: isPsychologyListExpanded,
            compactCount: Self.compactReportCount
        )
    }

    @ViewBuilder
    private func reportsListExpandButton(
        isExpanded: Bool,
        hasMore: Bool,
        accessibilityID: String,
        action: @escaping () -> Void
    ) -> some View {
        if hasMore {
            Button(action: action) {
                HStack(spacing: ExperienceSpacing.xxs) {
                    Text(isExpanded ? "Show Less" : "Show More")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(colors.secondaryText)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(colors.tertiaryText)
                }
                .padding(.vertical, ExperienceSpacing.xxs)
            }
            .buttonStyle(.experiencePlain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(accessibilityID)
            .accessibilityLabel(isExpanded ? "Show Less" : "Show More")
        }
    }

    private func performanceCard(_ card: ReportTypeCardModel) -> some View {
        let generating = viewModel.generatingPeriod == card.periodKey
        return ReportCard(
            systemImage: card.systemImage,
            title: card.title,
            subtitle: card.subtitle,
            trailingTitle: ReportCard.trailingTitle(
                for: generating ? "Generating…" : card.actionTitle,
                isGenerating: generating
            ),
            isGenerating: generating,
            onTap: { viewModel.primaryAction(for: card) }
        )
        .accessibilityIdentifier("reports.card.\(card.periodKey.rawValue)")
    }

    private var customReportCard: some View {
        ReportCard(
            systemImage: "calendar.badge.plus",
            title: "Custom",
            subtitle: "Generate a report for any date range.",
            trailingTitle: ReportCard.trailingTitle(for: "Choose Dates", isGenerating: false),
            onTap: { viewModel.openCustomRangeSheet() }
        )
        .accessibilityIdentifier("reports.card.custom")
    }

    private func yearlyCardView(_ card: YearlyReportCardModel) -> some View {
        let showsPicker = card.availableYears.count > 1
        return ReportCard(
            systemImage: card.systemImage,
            title: card.title,
            subtitle: card.subtitle,
            trailingTitle: ReportCard.trailingTitle(for: card.actionTitle, isGenerating: false),
            trailingBehavior: showsPicker
                ? .interactive { viewModel.primaryAction(for: card) }
                : .decorative,
            onTap: {
                guard !card.availableYears.isEmpty else { return }
                viewModel.primaryAction(for: card)
            }
        )
        .accessibilityIdentifier("reports.card.yearly")
    }

    private func psychologyCard(_ card: PsychologyReportCardModel) -> some View {
        let showsPeriodPicker = card.template.isPeriodic && card.availablePeriods.count > 1
        return ReportCard(
            systemImage: card.systemImage,
            title: card.title,
            subtitle: card.subtitle,
            trailingTitle: ReportCard.trailingTitle(for: card.actionTitle, isGenerating: false),
            trailingBehavior: showsPeriodPicker
                ? .interactive { viewModel.showPsychologyPeriodPicker(for: card) }
                : .decorative,
            onTap: { viewModel.openPsychologyReport(for: card) }
        )
        .accessibilityIdentifier("reports.psychology.\(card.template.rawValue)")
    }

    private func togglePerformanceSection() {
        ExperienceHaptics.play(.selection)
        ExperienceMotion.withAnimation(
            ExperienceMotion.selection,
            reduceMotion: reduceMotion
        ) {
            isPerformanceExpanded.toggle()
        }
    }

    private func togglePsychologySection() {
        ExperienceHaptics.play(.selection)
        ExperienceMotion.withAnimation(
            ExperienceMotion.selection,
            reduceMotion: reduceMotion
        ) {
            isPsychologyExpanded.toggle()
        }
    }

    private func togglePerformanceListExpanded() {
        ExperienceHaptics.play(.selection)
        ExperienceMotion.withAnimation(
            ExperienceMotion.selection,
            reduceMotion: reduceMotion
        ) {
            isPerformanceListExpanded.toggle()
        }
    }

    private func togglePsychologyListExpanded() {
        ExperienceHaptics.play(.selection)
        ExperienceMotion.withAnimation(
            ExperienceMotion.selection,
            reduceMotion: reduceMotion
        ) {
            isPsychologyListExpanded.toggle()
        }
    }

}

private enum ReportsCatalogPerformanceRow: Identifiable {
    case period(ReportTypeCardModel)
    case yearly(YearlyReportCardModel)
    case custom

    var id: String {
        switch self {
        case .period(let card):
            return "period-\(card.periodKey.rawValue)"
        case .yearly:
            return "yearly"
        case .custom:
            return "custom"
        }
    }
}

enum ReportsCatalogListVisibility {
    static func visibleItems<Element>(
        from all: [Element],
        listExpanded: Bool,
        compactCount: Int
    ) -> [Element] {
        guard !listExpanded, all.count > compactCount else { return all }
        return Array(all.prefix(compactCount))
    }
}

struct PsychologyReportPeriodPickerView: View {
    let periods: [PsychologyReportPeriodRef]
    var onSelect: (PsychologyReportPeriodRef) -> Void
    var onClose: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        NavigationStack {
            List(periods, id: \.self) { ref in
                Button {
                    onSelect(ref)
                } label: {
                    if let report = PsychologyReportSessionStore.shared.report(for: ref.reportID) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(report.dateRangeLabel)
                                .experienceStyle(.headline, color: colors.primaryText)
                            Text(NumberDisplay.tradeCount(report.performance.tradeCount))
                                .experienceStyle(.footnote, color: colors.secondaryText)
                        }
                    } else {
                        Text(ref.periodID)
                    }
                }
            }
            .experiencePlainListStyle()
            .navigationTitle("Choose Period")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
        }
    }
}

struct TradingReportYearPickerView: View {
    let years: [Int]
    var onSelect: (Int) -> Void
    var onClose: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        NavigationStack {
            List(years, id: \.self) { year in
                Button {
                    onSelect(year)
                } label: {
                    Text(String(year))
                        .experienceStyle(.headline, color: colors.primaryText)
                }
            }
            .experiencePlainListStyle()
            .navigationTitle("Choose Year")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
        }
        .accessibilityIdentifier("reports.yearly.picker")
    }
}
