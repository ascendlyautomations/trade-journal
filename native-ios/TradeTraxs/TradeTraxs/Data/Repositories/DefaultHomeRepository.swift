import Foundation

nonisolated struct DefaultHomeRepository: HomeRepository {
    private let supabase: SupabaseInfrastructure
    private let cache: CacheStack
    private let trades: DefaultTradeRepository

    init(
        supabase: SupabaseInfrastructure,
        cache: CacheStack = .placeholder(),
        session: any SessionProviding
    ) {
        self.supabase = supabase
        self.cache = cache
        self.trades = DefaultTradeRepository(supabase: supabase, cache: cache, session: session)
    }

    func dashboard(for profileID: ProfileID) async throws -> HomeDashboard {
        let interval = DateIntervalValue(
            start: Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date(),
            end: Date()
        )
        let summary = try await performance(for: profileID, interval: interval)
        return HomeDashboard(
            summary: summary,
            widgets: [
                HomeWidget(kind: .dailyPnL, isEnabled: true),
                HomeWidget(kind: .winRate, isEnabled: true),
                HomeWidget(kind: .streak, isEnabled: true),
            ],
            insights: [],
            shortcutDestinations: ["trades", "calendar", "feed"],
            refreshedAt: Date()
        )
    }

    func performance(
        for profileID: ProfileID,
        interval: DateIntervalValue
    ) async throws -> PerformanceSummary {
        let statistics = try await trades.statistics(for: profileID, interval: interval)
        struct Params: Encodable { var p_user_id: String }
        let data = try JSONEncoder().encode(Params(p_user_id: profileID.rawValue))
        var streak = 0
        if let raw = try? await supabase.database.rpcData(
            functionName: "user_streak_milestone_bundle",
            parametersJSON: data
        ),
           let rows = try? JSONDecoder().decode([HomeDTO.StreakBundle].self, from: raw),
           let bundle = rows.first
        {
            streak = (bundle.trade_count ?? 0) > 0 ? 1 : 0
        }
        return PerformanceSummary(
            interval: interval,
            statistics: statistics,
            bestTradeID: nil,
            worstTradeID: nil,
            currentStreakDays: streak
        )
    }
}
