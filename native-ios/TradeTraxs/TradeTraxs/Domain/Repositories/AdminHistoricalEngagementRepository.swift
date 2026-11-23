import Foundation

nonisolated struct AdminHistoricalImportQuality: Sendable, Hashable, Codable {
    var manualEntered: Int
    var unsetImportSource: Int
    var csv: Int
    var broker: Int
    var other: Int
    var bulkInitialImportRows: Int
    var organicTradesLogged: Int
    var tradeDateBeforeCreatedDayRows: Int
    var nullTradeDateRows: Int
}

nonisolated struct AdminHistoricalEngagementMeta: Sendable, Hashable, Codable {
    var notes: [String]
    var isContentActivityNotSessions: Bool
    var maxSeriesDays: Int
    var periodStart: String?
    var periodEnd: String?
    var rangeMode: String?
    var activityFilter: String?
    var retentionObservationEnd: String?
}

nonisolated struct AdminHistoricalEngagementOverview: Sendable, Hashable, Codable {
    var engagedDau: Int
    var engagedWau: Int
    var engagedMau: Int
    var activeTradersDau: Int
    var activeCreatorsDau: Int
    var activeMessengersDau: Int
    var newSignupsInPeriod: Int
    var accountsCreatedInPeriod: Int
}

nonisolated struct AdminHistoricalTradingSeries: Sendable, Hashable, Codable {
    var tradesLoggedPerDay: [AdminUsageDailyCount]
    var organicTradesLoggedPerDay: [AdminUsageDailyCount]
    var bulkImportTradesPerDay: [AdminUsageDailyCount]
    var tradesByExecutionDatePerDay: [AdminUsageDailyCount]
    var activeTradersPerDay: [AdminUsageDailyCount]
    var returningTradersPerDay: [AdminUsageDailyCount]
    var importQuality: AdminHistoricalImportQuality
}

nonisolated struct AdminHistoricalSocialSeries: Sendable, Hashable, Codable {
    var postsPerDay: [AdminUsageDailyCount]
    var profilePostsPerDay: [AdminUsageDailyCount]
    var reelsPerDay: [AdminUsageDailyCount]
    var commentsPerDay: [AdminUsageDailyCount]
    var likesPerDay: [AdminUsageDailyCount]
    var followsPerDay: [AdminUsageDailyCount]
    var messagesPerDay: [AdminUsageDailyCount]
    var activeCreatorsPerDay: [AdminUsageDailyCount]
    var activeMessengersPerDay: [AdminUsageDailyCount]
}

nonisolated struct AdminHistoricalEngagementSeries: Sendable, Hashable, Codable {
    var signupsPerDay: [AdminUsageDailyCount]
    var accountsCreatedPerDay: [AdminUsageDailyCount]
    var engagedUsersPerDay: [AdminUsageDailyCount]
    var returningEngagedUsersPerDay: [AdminUsageDailyCount]
    var returningCreatorsPerDay: [AdminUsageDailyCount]
}

nonisolated struct AdminHistoricalEngagementBundle: Sendable, Hashable, Codable {
    var seriesDays: Int
    var meta: AdminHistoricalEngagementMeta
    var overview: AdminHistoricalEngagementOverview
    var retentionD1Rate: Double?
    var retentionD7Rate: Double?
    var retentionD30Rate: Double?
    var cohortSignupsTotal: Int
    var retentionInsufficientData: Bool
    var retentionD1MatureCohortSize: Int
    var retentionD7MatureCohortSize: Int
    var retentionD30MatureCohortSize: Int
    var retentionDefinition: String
    var trading: AdminHistoricalTradingSeries
    var social: AdminHistoricalSocialSeries
    var series: AdminHistoricalEngagementSeries
}

nonisolated enum AdminHistoricalEngagementDefinition {
    static let engagedUsers =
        "Distinct users per UTC day with organic trade logging or social/messaging content created that day (created_at). Not app sessions."

    static let executionDates =
        "Trade counts by trade_date (execution). Reflects market dates, not app usage."

    static let maxSeriesDays = 365
}

nonisolated protocol AdminHistoricalEngagementRepository: Sendable {
    func fetchHistoricalBundle(query: AdminHistoricalEngagementQuery) async throws -> AdminHistoricalEngagementBundle
}