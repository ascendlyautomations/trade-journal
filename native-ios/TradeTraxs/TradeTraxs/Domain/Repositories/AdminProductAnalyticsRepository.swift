import Foundation

nonisolated struct AdminProductFeatureUsageRow: Sendable, Hashable, Codable {
    var feature: String
    var uniqueUsers: Int
    var webUniqueUsers: Int
    var iosUniqueUsers: Int
    var useCount: Int
}

nonisolated struct AdminProductAnalyticsMeta: Sendable, Hashable, Codable {
    var productTrackingStartDate: String?
    var productEngagementAvailable: Bool
    var retentionMetricsAvailable: Bool
    var previewFunnelAvailable: Bool
    var notes: [String]
}

nonisolated struct AdminProductAnalyticsOverview: Sendable, Hashable, Codable {
    var totalUsers: Int
    var newSignupsToday: Int
    var productDau: Int?
    var productWau: Int?
    var productMau: Int?
    var dauMauRatio: Double?
}

nonisolated struct AdminProductImportTotals: Sendable, Hashable, Codable {
    var manualEntered: Int
    var unsetImportSource: Int
    var csv: Int
    var broker: Int
    var other: Int
}

/// Nullable count for days before product tracking (`count` = nil → unavailable).
nonisolated struct AdminProductDailyCount: Sendable, Hashable, Codable {
    var day: String
    var count: Int?
}

nonisolated struct AdminProductPreviewFunnel: Sendable, Hashable, Codable {
    var starts: Int
    var exits: Int
    var upgradeTaps: Int
    var startToUpgradeRate: Double?
}

nonisolated struct AdminProductAnalyticsSeries: Sendable, Hashable, Codable {
    var signupsPerDay: [AdminUsageDailyCount]
    var productActiveUsersPerDay: [AdminProductDailyCount]
    var returningUsersPerDay: [AdminUsageDailyCount]
    var tradesCreatedPerDay: [AdminUsageDailyCount]
    var activeTradersPerDay: [AdminUsageDailyCount]
    var profileViewsPerDay: [AdminUsageDailyCount]
    var uniqueProfileViewersPerDay: [AdminUsageDailyCount]
    var postsPerDay: [AdminUsageDailyCount]
    var featureEngagementPerDay: [AdminUsageDailyCount]
    var previewStartsPerDay: [AdminUsageDailyCount]
    var previewExitsPerDay: [AdminUsageDailyCount]
    var previewUpgradeTapsPerDay: [AdminUsageDailyCount]
}

nonisolated struct AdminProductAnalyticsBundle: Sendable, Hashable, Codable {
    var seriesDays: Int
    var meta: AdminProductAnalyticsMeta
    var overview: AdminProductAnalyticsOverview
    var retentionD1Rate: Double?
    var retentionD7Rate: Double?
    var retentionD30Rate: Double?
    var cohortSampleSignups: Int
    var retentionInsufficientData: Bool
    var retentionD1MatureCohortSize: Int
    var retentionD7MatureCohortSize: Int
    var retentionD30MatureCohortSize: Int
    var tradesPerActiveTraderLatestDay: Double?
    var importTotals: AdminProductImportTotals
    var topFeatures: [AdminProductFeatureUsageRow]
    var previewFunnel: AdminProductPreviewFunnel
    var previewAvailable: Bool
    var series: AdminProductAnalyticsSeries
}

enum AdminProductAnalyticsDefinition {
    static let productDau =
        "Distinct users per UTC day with session or app-open engagement (product rollups). Broker sync is excluded."

    static let legacyActivityDau =
        "Legacy: distinct users with trade/post/support activity in a rolling window, not product sessions."

    static let maxProductSeriesDays = 90
}

nonisolated protocol AdminProductAnalyticsRepository: Sendable {
    func fetchProductBundle(seriesDays: Int) async throws -> AdminProductAnalyticsBundle
}