import Foundation

nonisolated struct DefaultAdminUsageAnalyticsRepository: AdminUsageAnalyticsRepository {
    private let supabase: SupabaseInfrastructure

    init(supabase: SupabaseInfrastructure) {
        self.supabase = supabase
    }

    func fetchBundle(seriesDays: Int) async throws -> AdminUsageAnalyticsBundle {
        let days = max(1, min(seriesDays, 365))
        let body = try JSONSerialization.data(withJSONObject: ["p_series_days": days], options: [])
        do {
            let data = try await supabase.database.rpcData(
                functionName: "admin_analytics_bundle",
                parametersJSON: body
            )
            var bundle = try AdminUsageAnalyticsParsing.parseBundle(from: data)
            bundle.series = AdminUsageAnalyticsSeries(
                usersPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.series.usersPerDay, seriesDays: bundle.seriesDays),
                activeUsersPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.series.activeUsersPerDay, seriesDays: bundle.seriesDays),
                tradesPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.series.tradesPerDay, seriesDays: bundle.seriesDays),
                postsPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.series.postsPerDay, seriesDays: bundle.seriesDays),
                reelsPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.series.reelsPerDay, seriesDays: bundle.seriesDays),
                commentsPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.series.commentsPerDay, seriesDays: bundle.seriesDays),
                likesPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.series.likesPerDay, seriesDays: bundle.seriesDays),
                followsPerDay: AdminUsageAnalyticsParsing.normalizeSeries(bundle.series.followsPerDay, seriesDays: bundle.seriesDays)
            )
            return bundle
        } catch {
            let message = error.localizedDescription.lowercased()
            if message.contains("not authorized") {
                throw AdminUsageAnalyticsError.notAuthorized
            }
            throw error
        }
    }
}
