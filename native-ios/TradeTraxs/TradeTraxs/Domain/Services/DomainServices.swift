import Foundation

/// Pure trade analytics — no I/O.
nonisolated protocol TradeAnalysisService: Sendable {
    func analyze(trade: Trade, notes: [TradeNote]) -> TradeAnalysis
}

/// Aggregates trade sets into performance statistics.
nonisolated protocol PerformanceCalculationService: Sendable {
    func summarize(trades: [Trade], interval: DateIntervalValue) -> TradeStatistics
    func performanceSummary(trades: [Trade], interval: DateIntervalValue) -> PerformanceSummary
}

/// Risk / RR helpers for drafts and closed trades.
nonisolated protocol RiskService: Sendable {
    func riskReward(entry: Decimal, exit: Decimal, stop: Decimal?, side: TradeSide) -> Decimal?
    func validatesRisk(for draft: TradeDraft) -> TradeValidationError?
}

/// Daily / win streak computation.
nonisolated protocol StreakService: Sendable {
    func currentStreakDays(from days: [JournalDay], asOf date: Date) -> Int
}

/// Achievement eligibility from trading outcomes.
nonisolated protocol AchievementService: Sendable {
    func evaluate(profileID: ProfileID, trades: [Trade], accounts: [TradingAccount]) -> [Achievement]
}

/// Orders feed candidates without network access.
nonisolated protocol FeedRankingService: Sendable {
    func rank(_ items: [FeedItem], scope: FeedScope) -> [FeedItem]
}

/// Decides whether an activity should create an inbox notification.
nonisolated protocol NotificationDecisionService: Sendable {
    func shouldNotify(
        kind: ActivityNotificationKind,
        actorID: ProfileID,
        recipientID: ProfileID
    ) -> Bool
}

/// Builds calendar events from journal days / reports.
nonisolated protocol CalendarService: Sendable {
    func events(from days: [JournalDay], profileID: ProfileID) -> [CalendarEvent]
}

/// Ranks heterogeneous search hits.
nonisolated protocol SearchRankingService: Sendable {
    func rank(_ results: [SearchResult], query: String) -> [SearchResult]
}
