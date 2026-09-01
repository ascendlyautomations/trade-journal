import Foundation
import Observation

/// Reports catalog — web Trading Reports periods (this/last week & month).
@Observable
@MainActor
final class ReportsScreenViewModel: ScreenLifecycle {
    typealias State = ReportsState

    private(set) var state = ReportsState()

    private let tradingReports: any TradingReportRepository
    private let navigationCoordinator: NavigationCoordinator
    private var bootstrapTask: Task<Void, Never>?

    init(
        tradingReports: any TradingReportRepository,
        navigationCoordinator: NavigationCoordinator
    ) {
        self.tradingReports = tradingReports
        self.navigationCoordinator = navigationCoordinator
        state.cards = Self.placeholderCards()
    }

    // MARK: - Facades

    var phase: ReportsState.Phase { state.phase }
    var cards: [ReportTypeCardModel] { state.cards }
    var isRefreshing: Bool { state.isRefreshing }
    var generatingPeriod: TradingReportPeriodKey? { state.generatingPeriod }

    // MARK: - Lifecycle

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

    // MARK: - Actions

    func primaryAction(for card: ReportTypeCardModel) {
        ExperienceHaptics.play(.selection)
        Task { await openReport(for: card.periodKey) }
    }

    func openReport(for periodKey: TradingReportPeriodKey) async {
        if let existing = state.snapshot?.report(for: periodKey) {
            _ = existing
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
            failed.cards = Self.cards(
                from: failed.snapshot,
                generating: nil
            )
            state = failed
        }
    }

    // MARK: - Private

    private func performBootstrap(forceNetwork: Bool) async {
        if !state.didBootstrap {
            var loading = state
            loading.phase = .loading
            state = loading
        }

        do {
            let result = try await ReportsBootstrap.load(
                ReportsBootstrap.Context(
                    tradingReports: tradingReports,
                    forceNetwork: forceNetwork
                )
            )
            var next = state
            next.snapshot = result.snapshot
            next.cards = result.cards
            next.lastUpdated = result.loadedAt
            next.didBootstrap = true
            next.generatingPeriod = nil
            next.phase = .loaded
            state = next
        } catch {
            var next = state
            next.phase = .failed(Self.userFacingMessage(for: error))
            next.generatingPeriod = nil
            state = next
        }
    }

    private static func placeholderCards() -> [ReportTypeCardModel] {
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

    private static func cards(
        from snapshot: TradingReportsSnapshot?,
        generating: TradingReportPeriodKey?
    ) -> [ReportTypeCardModel] {
        TradingReportPeriodKey.allCases.map { key in
            if generating == key {
                return ReportTypeCardModel(
                    periodKey: key,
                    title: key.catalogTitle,
                    subtitle: key.catalogSubtitle,
                    systemImage: key.systemImage,
                    actionTitle: ReportAvailability.generating.actionTitle,
                    availability: .generating,
                    dateRangeLabel: nil
                )
            }
            let report = snapshot?.report(for: key)
            let availability: ReportAvailability = report == nil ? .readyToGenerate : .ready
            return ReportTypeCardModel(
                periodKey: key,
                title: key.catalogTitle,
                subtitle: report?.dateRangeLabel ?? key.catalogSubtitle,
                systemImage: key.systemImage,
                actionTitle: availability.actionTitle,
                availability: availability,
                dateRangeLabel: report?.dateRangeLabel
            )
        }
    }

    /// Trade AI–style copy — never raw NetworkError strings.
    static func userFacingMessage(for error: Error) -> String {
        if let app = error as? AppError {
            return UserFacingError.map(app).message
        }
        if let network = error as? NetworkError {
            switch network {
            case .connectivity:
                return "You're offline. Reconnect to load your trading reports."
            case .timeout:
                return "The request timed out. Please try again."
            case .validation(_, let message) where message.lowercased().contains("base url"):
                return "Reports aren't available in this build. Check API configuration."
            default:
                return UserFacingError.map(network).message
            }
        }
        return "We couldn't load your reports. Please try again."
    }
}
