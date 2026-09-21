import Foundation
import GRDB

struct ProfileAnalyticsSnapshotRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "profile_analytics_snapshot"

    var viewer_id: String
    var subject_profile_id: String
    var contract_version: String
    var visibility_identity: String
    var public_revision: Int64
    var fetched_at: String
    var modes_payload_json: Data
}
