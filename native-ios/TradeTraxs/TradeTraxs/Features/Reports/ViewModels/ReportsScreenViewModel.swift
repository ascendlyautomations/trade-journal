import Foundation
import Observation

/// Reports catalog, performance + psychology report groups.
@Observable
@MainActor
final class ReportsScreenViewModel: ScreenLifecycle {
    typealias State = ReportsState

    private(set) var state = ReportsState()
    var periodPickerPeriods: [PsychologyReportPeriodRef] = []
    var availableYears: [Int] = []
    var showsPeriodPicker = false
    var showsYearPicker = false
    var showsCustomRangeSheet = false
    var showsPsychologyCustomRangeSheet = false
    var draftCustomRangeStart: Date?
    var draftCustomRangeEnd: Date?
    var draftCustomMonth: Int = 1
    var draftCustomYear: Int = 2_026
    private(set) var filters = TradingReportSessionStore.shared.filters
    private(set) var accounts: [TradingAccount] = []
    private(set) var profileID: ProfileID?

    private let tradingReports: any TradingReportRepository
    private let psychologyReports: any PsychologyReportRepository
    private let navigationCoordinator: NavigationCoordinator
    private let trades: (any TradeRepository)?
    private let session: (any SessionProviding)?
    private let detailCache: DetailPresentationCache?
    private var bootstrapTask: Task<Void, Never>?

    init(
        tradingReports: any TradingReportRepository,
        psychologyReports: any PsychologyReportRepository,
        navigationCoordinator: NavigationCoordinator,
        trades: (any TradeRepository)? = nil,
        session: (any SessionProviding)? = nil,
        detailCache: DetailPresentationCache? = nil
    ) {
        self.tradingReports = tradingReports
        self.psychologyReports = psychologyReports
        self.navigationCoordinator = navigationCoordinator
        self.trades = trades
        self.session = session
        self.detailCache = detailCache
        state.cards = Self.placeholderPerformanceCards()
        state.psychologyCards = Self.placeholderPsychologyCards()
    }

    var accountsForMenu: [TradingAccount] {
        let selectedID: TradingAccountID? = {
            if case .account(let id) = filters.accountFilter { return id }
            return nil
        }()
        return OwnerAccountDropdownSupport.menuAccounts(
            profileID: profileID,
            fallback: accounts,
            preservingSelection: selectedID,
            detailCache: detailCache
        )
    }

    var accountFilterTitle: String {
        OwnerAccountFilterMenuSupport.menuTitle(
            filter: filters.accountFilter,
            accounts: accounts,
            profileID: profileID
        )
    }

    func setAccountFilter(_ filter: DashboardAccountFilter) {
        let resolved = OwnerAccountMutationSync.reconciledAccountFilter(
            filter,
            accounts: accounts,
            profileID: profileID
        )
        guard filters.accountFilter != resolved else { return }
        ExperienceHaptics.play(.selection)
        filters.accountFilter = resolved
        TradingReportSessionStore.shared.filters.accountFilter = resolved
        Task { await refresh() }
    }

    func openManageAccounts() {
        navigationCoordinator.pushHome(.settings(.tradingAccounts))
    }

    func openTradeAIHub() {
        ExperienceHaptics.play(.selection)
        if ProAccessGate.presentFeatureIfNeeded(.aiAnalyst, profileID: profileID) {
            return
        }
        navigationCoordinator.pushHome(.generalTradeCoach)
    }

    func openManageCopyTradingGroups() {
        navigationCoordinator.pushHome(.settings(.copyTradingAccounts))
    }

    func handleAccountMutation() {
        guard let profileID else { return }
        guard let loaded = OwnerAccountMutationSync.sessionAccounts(
            profileID: profileID,
            detailCache: detailCache
        ) else { return }
        accounts = loaded.filter(\.isActive)
        OwnerAccountMutationSync.seedDetailCacheIfNeeded(loaded, profileID: profileID, detailCache: detailCache)
        sanitizeAccountFilter()
    }

    func handleCopyTradingGroupsMutation() {
        let previous = filters.accountFilter
        sanitizeAccountFilter()
        guard filters.accountFilter != previous else { return }
        Task { await refresh() }
    }

    func syncFiltersFromSession() {
        filters = TradingReportSessionStore.shared.filters
    }

    var phase: ReportsState.Phase { state.phase }
    var cards: [ReportTypeCardModel] { state.cards }
    var yearlyCard: YearlyReportCardModel? { state.yearlyCard }
    var psychologyCards: [PsychologyReportCardModel] { state.psychologyCards }
    var isRefreshing: Bool { state.isRefreshing }
    var generatingPeriod: TradingReportPeriodKey? { state.generatingPeriod }

    func bootstrapIfNeeded() async {
        guard bootstrapTask == nil, !state.didBootstrap else { return }
        bootstrapTask = Task { await performBootstrap(forceNetwork: false) }
        await bootstrapTask?.value
        bootstrapTask = nil
    }

    func refresh() async {
        var next = state
        next.isRefreshing = true
        state = next
        await performBootstrap(forceNetwork: true)
        next = state
        next.isRefreshing = false
        state = next
    }

    func loadMore() async {}
    func subscribeRealtime() {}
    func unsubscribeRealtime() {}

    func primaryAction(for card: ReportTypeCardModel) {
        ExperienceHaptics.play(.selection)
        Task { await openPerformanceReport(for: card.periodKey) }
    }

    func primaryAction(for yearlyCard: YearlyReportCardModel) {
        ExperienceHaptics.play(.selection)
        if yearlyCard.availableYears.count > 1 {
            availableYears = yearlyCard.availableYears
            showsYearPicker = true
        } else if let year = yearlyCard.availableYears.first {
            openYearlyReport(year: year)
        }
    }

    func openYearlyReport(year: Int) {
        showsYearPicker = false
        ReportsNavigation.openYearlyDetail(year: year, using: navigationCoordinator)
    }

    func openCustomRangeSheet() {
        ExperienceHaptics.play(.selection)
        let defaults = TradingReportCustomRangeSupport.defaultMonthSelection()
        draftCustomYear = defaults.year
        draftCustomMonth = defaults.month
        draftCustomRangeStart = defaults.start
        draftCustomRangeEnd = defaults.end
        showsCustomRangeSheet = true
    }

    var customRangeValidationMessage: String? {
        TradingReportCustomRangeSupport.validationMessage(
            start: draftCustomRangeStart,
            end: draftCustomRangeEnd
        )
    }

    var canGenerateCustomReport: Bool {
        TradingReportCustomRangeSupport.canGenerate(
            start: draftCustomRangeStart,
            end: draftCustomRangeEnd
        )
    }

    func applyQuickMonthSelection() {
        let range = TradingReportCustomRangeSupport.monthRange(
            year: draftCustomYear,
            month: draftCustomMonth
        )
        draftCustomRangeStart = range.start
        draftCustomRangeEnd = range.end
    }

    func generateCustomReport() {
        guard canGenerateCustomReport,
              let start = draftCustomRangeStart,
              let end = draftCustomRangeEnd
        else { return }
        ExperienceHaptics.play(.selection)
        let calendar = TradingReportPeriods.eastern
        let interval = DashboardScopeFilterSupport.normalizedCustomInterval(
            start: start,
            end: end,
            calendar: calendar
        )
        let ref = TradingReportCustomRangeRef.from(interval: interval)
        showsCustomRangeSheet = false
        ReportsNavigation.openDetail(ref.reportID, using: navigationCoordinator)
    }

    func openPsychologyCustomRangeSheet() {
        ExperienceHaptics.play(.selection)
        let defaults = TradingReportCustomRangeSupport.defaultMonthSelection()
        draftCustomYear = defaults.year
        draftCustomMonth = defaults.month
        draftCustomRangeStart = defaults.start
        draftCustomRangeEnd = defaults.end
        showsPsychologyCustomRangeSheet = true
    }

    func generateCustomPsychologyReport() {
        guard canGenerateCustomReport,
              let start = draftCustomRangeStart,
              let end = draftCustomRangeEnd
        else { return }
        ExperienceHaptics.play(.selection)
        let calendar = TradingReportPeriods.eastern
        let interval = DashboardScopeFilterSupport.normalizedCustomInterval(
            start: start,
            end: end,
            calendar: calendar
        )
        let periodID = PsychologyReportTimeScope.custom(interval).periodID
        let ref = PsychologyReportPeriodRef(template: .custom, periodID: periodID)
        showsPsychologyCustomRangeSheet = false
        ReportsNavigation.openPsychologyDetail(ref.reportID, using: navigationCoordinator)
    }

    func primaryAction(for card: PsychologyReportCardModel) {
        if card.template.isPeriodic, card.availablePeriods.count > 1 {
            showPsychologyPeriodPicker(for: card)
        } else {
            openPsychologyReport(for: card)
        }
    }

    func openPsychologyReport(for card: PsychologyReportCardModel) {
        ExperienceHaptics.play(.selection)
        guard let ref = card.periodRef else { return }
        ReportsNavigation.openPsychologyDetail(ref.reportID, using: navigationCoordinator)
    }

    func showPsychologyPeriodPicker(for card: PsychologyReportCardModel) {
        ExperienceHaptics.play(.selection)
        periodPickerPeriods = card.availablePeriods
        showsPeriodPicker = true
    }

    func openPsychologyPeriod(_ ref: PsychologyReportPeriodRef) {
        showsPeriodPicker = false
        ReportsNavigation.openPsychologyDetail(ref.reportID, using: navigationCoordinator)
    }

    private func openPerformanceReport(for periodKey: TradingReportPeriodKey) async {
        if state.snapshot?.report(for: periodKey) != nil {
            ReportsNavigation.openDetail(periodKey.reportID, using: navigationCoordinator)
            return
        }

        var next = state
        next.generatingPeriod = periodKey
        next.cards = next.cards.map { card in
            guard card.periodKey == periodKey else { return card }
            var updated = card
            updated.availability = .generating
            updated.actionTitle = ReportAvailability.generating.actionTitle
            return updated
        }
        state = next

        do {
            _ = try await tradingReports.report(for: periodKey, forceNetwork: false)
            await performBootstrap(forceNetwork: false)
            ReportsNavigation.openDetail(periodKey.reportID, using: navigationCoordinator)
        } catch {
            var failed = state
            failed.generatingPeriod = nil
            failed.phase = .failed(Self.userFacingMessage(for: error))
            state = failed
        }
    }

    private func performBootstrap(forceNetwork: Bool) async {
        if !state.didBootstrap {
            var loading = state
            loading.phase = .loading
            state = loading
        }

        syncFiltersFromSession()
        await loadAccountsIfNeeded()
        sanitizeAccountFilter()

        do {
            async let performance = ReportsBootstrap.load(
                ReportsBootstrap.Context(tradingReports: tradingReports, forceNetwork: forceNetwork)
            )
            async let psychology = PsychologyReportsBootstrap.load(
                PsychologyReportsBootstrap.Context(
                    psychologyReports: psychologyReports,
                    forceNetwork: forceNetwork
                )
            )
            let (perfResult, psychResult) = try await (performance, psychology)

            var next = state
            next.snapshot = perfResult.snapshot
            next.cards = perfResult.cards
            next.yearlyCard = perfResult.yearlyCard
            availableYears = perfResult.availableYears
            next.psychologySnapshot = psychResult.snapshot
            next.psychologyCards = psychResult.cards
            next.lastUpdated = max(perfResult.loadedAt, psychResult.loadedAt)
            next.didBootstrap = true
            next.generatingPeriod = nil
            next.generatingPsychologyTemplate = nil
            next.phase = .loaded
            state = next
        } catch {
            var next = state
            next.phase = .failed(Self.userFacingMessage(for: error))
            next.generatingPeriod = nil
            state = next
        }
    }

    private func loadAccountsIfNeeded() async {
        if let userID = await session?.currentUserID {
            profileID = ProfileID(userID.rawValue)
        }
        guard let profileID else { return }
        if TraxsProPreviewSupport.isReportsPreviewActive, let trades {
            do {
                accounts = try await trades.accounts(for: profileID).filter(\.isActive)
            } catch {
                accounts = DemoCanonicalDataset.accounts(owner: profileID).filter(\.isActive)
            }
            return
        }
        guard accounts.isEmpty, let trades else { return }
        do {
            let loaded = try await trades.accounts(for: profileID)
            accounts = loaded.filter(\.isActive)
        } catch {
            // Account menu falls back to all accounts only.
        }
    }

    private func sanitizeAccountFilter() {
        let sanitized = OwnerAccountMutationSync.reconciledAccountFilter(
            filters.accountFilter,
            accounts: accounts,
            profileID: profileID
        )
        guard sanitized != filters.accountFilter else { return }
        filters.accountFilter = sanitized
        TradingReportSessionStore.shared.filters.accountFilter = sanitized
    }

    private static func placeholderPerformanceCards() -> [ReportTypeCardModel] {
        TradingReportPeriodKey.allCases.map { key in
            ReportTypeCardModel(
                periodKey: key,
                title: key.catalogTitle,
                subtitle: key.catalogSubtitle,
                systemImage: key.systemImage,
                actionTitle: ReportAvailability.readyToGenerate.actionTitle,
                availability: .readyToGenerate,
                dateRangeLabel: nil
            )
        }
    }

    private static func placeholderPsychologyCards() -> [PsychologyReportCardModel] {
        PsychologyReportsBootstrap.buildCards(
            from: PsychologyReportsSnapshot(
                reports: [:],
                computedAt: 0,
                catalogPeriods: []
            )
        )
    }

    static func userFacingMessage(for error: Error) -> String {
        if let app = error as? AppError {
            return UserFacingError.map(app).message
        }
        if let network = error as? NetworkError {
            switch network {
            case .connectivity:
                return "You're offline. Reconnect to load your reports."
            case .timeout:
                return "The request timed out. Please try again."
            default:
                return UserFacingError.map(network).message
            }
        }
        return "We couldn't load your reports. Please try again."
    }
}
