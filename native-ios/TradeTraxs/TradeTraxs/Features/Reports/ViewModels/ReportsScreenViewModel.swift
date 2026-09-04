import Foundation
import Observation

/// Reports catalog — performance + psychology report groups.
@Observable
@MainActor
final class ReportsScreenViewModel: ScreenLifecycle {
    typealias State = ReportsState

    private(set) var state = ReportsState()
    var periodPickerPeriods: [PsychologyReportPeriodRef] = []
    var availableYears: [Int] = []
    var showsPeriodPicker = false
    var showsYearPicker = false

    private let tradingReports: any TradingReportRepository
    private let psychologyReports: any PsychologyReportRepository
    private let navigationCoordinator: NavigationCoordinator
    private var bootstrapTask: Task<Void, Never>?

    init(
        tradingReports: any TradingReportRepository,
        psychologyReports: any PsychologyReportRepository,
        navigationCoordinator: NavigationCoordinator
    ) {
        self.tradingReports = tradingReports
        self.psychologyReports = psychologyReports
        self.navigationCoordinator = navigationCoordinator
        state.cards = Self.placeholderPerformanceCards()
        state.psychologyCards = Self.placeholderPsychologyCards()
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
        PsychologyReportTemplate.allCases.map { template in
            PsychologyReportCardModel(
                template: template,
                title: template.catalogTitle,
                subtitle: template.catalogSubtitle,
                systemImage: template.systemImage,
                actionTitle: "View Report",
                availability: .readyToGenerate,
                periodRef: nil,
                availablePeriods: []
            )
        }
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
