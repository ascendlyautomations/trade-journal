import Foundation

nonisolated struct AdminLifecycleFunnelStage: Sendable, Hashable, Codable {
    var id: String
    var label: String
    var count: Int
}

nonisolated struct AdminLifecycleAnalyticsBundle: Sendable, Hashable, Codable {
    var seriesDays: Int
    var activationStages: [AdminLifecycleFunnelStage]
    var traxsProStages: [AdminLifecycleFunnelStage]
    var sessionD1Rate: Double?
    var sessionD7Rate: Double?
    var sessionD1MatureCohortSize: Int
    var sessionRetentionInsufficientData: Bool
    var notes: [String]
}

nonisolated protocol AdminLifecycleAnalyticsRepository: Sendable {
    func fetchLifecycleBundle(query: AdminLifecycleAnalyticsQuery) async throws -> AdminLifecycleAnalyticsBundle
}