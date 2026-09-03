import Foundation
import Observation

@Observable
@MainActor
final class CheckInHistoryViewModel: ScreenLifecycle {
    typealias State = CheckInHistoryState

    private(set) var state = CheckInHistoryState()

    private let dailyCheckIns: any TraderDailyCheckInRepository
    private let trades: any TradeRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let navigationCoordinator: NavigationCoordinator

    init(
        dailyCheckIns: any TraderDailyCheckInRepository,
        trades: any TradeRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        navigationCoordinator: NavigationCoordinator
    ) {
        self.dailyCheckIns = dailyCheckIns
        self.trades = trades
        self.session = session
        self.detailCache = detailCache
        self.navigationCoordinator = navigationCoordinator
    }

    var phase: CheckInHistoryState.Phase { state.phase }
    var summaries: [CheckInHistoryDaySummary] { state.summaries }

    func bootstrapIfNeeded() async {
        guard !state.didBootstrap else { return }
        await load(forceNetwork: false)
    }

    func refresh() async {
        await load(forceNetwork: true)
    }

    func loadMore() async {}
    func subscribeRealtime() {}
    func unsubscribeRealtime() {}

    func openDay(_ summary: CheckInHistoryDaySummary) {
        navigationCoordinator.pushHome(.checkInDay(summary.dateKey))
    }

    private func load(forceNetwork: Bool) async {
        state.phase = .loading
        do {
            guard let userID = await session.currentUserID else {
                state.phase = .failed("Sign in to view check-in history.")
                return
            }
            let profileID = ProfileID(userID.rawValue)
            let startKey = CheckInHistoryAggregator.startDateKey()
            let endKey = TraderPsychologyAnalyticsFoundation.todayCheckInDateKey()

            let loadedTrades: [Trade]
            if ProfileSectionSupport.isLocalDevelopmentProfile(profileID) {
                loadedTrades = ProfileTradeFixtures.samples(owner: profileID)
            } else {
                loadedTrades = try await SessionOwnerTradesStore.shared.trades(
                    for: profileID,
                    detailCache: detailCache,
                    repository: trades,
                    forceNetwork: forceNetwork
                )
            }
            let eligible = loadedTrades.filter { $0.mode != .backtest }
            let checkIns = try await dailyCheckIns.checkIns(for: profileID, from: startKey, to: endKey)
            let summaries = CheckInHistoryAggregator.buildSummaries(checkIns: checkIns, trades: eligible)

            CheckInHistorySessionStore.shared.update(
                summaries: summaries,
                checkIns: checkIns,
                trades: eligible
            )
            state.summaries = summaries
            state.didBootstrap = true
            state.phase = .loaded
        } catch {
            state.phase = .failed(error.localizedDescription)
        }
    }
}

struct CheckInHistoryState: ScreenStateModeling {
    enum Phase: Equatable { case idle, loading, loaded, failed(String) }
    var phase: Phase = .idle
    var summaries: [CheckInHistoryDaySummary] = []
    var didBootstrap = false

    var screenPhase: ScreenPhase {
        switch phase {
        case .idle: return .idle
        case .loading: return .loading
        case .loaded: return .loaded
        case .failed(let message): return .failed(message)
        }
    }

    var screenErrorMessage: String? {
        if case .failed(let message) = phase { return message }
        return nil
    }

    var pagination: ScreenPaginationSnapshot { .none }
}
