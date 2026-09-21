import Foundation

nonisolated struct AnalyticsRevisionV1: Codable, Sendable, Equatable {
    var revision: Int64
    var updated_at: String

    var revisionInt: Int64 { revision }
}
