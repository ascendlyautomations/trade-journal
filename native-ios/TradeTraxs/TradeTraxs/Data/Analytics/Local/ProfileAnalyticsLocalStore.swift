import Foundation
import GRDB

extension AnalyticsLocalStore {
    nonisolated struct ProfileAnalyticsCacheKey: Sendable, Equatable {
        var viewerID: String
        var subjectProfileID: String
        var contractVersion: String
        var visibilityIdentity: String
    }

    nonisolated struct ProfileAnalyticsSnapshot: Sendable {
        var publicRevision: Int64
        var fetchedAt: String
        var modeResults: [ProfileStatisticsMetrics.Mode: ProfileStatisticsMetrics.Result]
        var visibilityIdentity: String
    }

    func readProfileAnalyticsSnapshot(
        key: ProfileAnalyticsCacheKey
    ) async throws -> ProfileAnalyticsSnapshot? {
        let started = Date()
        let queue = try await database.databaseQueue()
        let row = try await queue.read { db in
            try ProfileAnalyticsSnapshotRecord
                .filter(Column("viewer_id") == key.viewerID)
                .filter(Column("subject_profile_id") == key.subjectProfileID)
                .filter(Column("contract_version") == key.contractVersion)
                .filter(Column("visibility_identity") == key.visibilityIdentity)
                .fetchOne(db)
        }
        guard let row else {
            ProfileAnalyticsGRDBProbe.logMiss(
                viewer: key.viewerID,
                subject: key.subjectProfileID
            )
            return nil
        }
        let modes = try ProfileAnalyticsModesCodec.decode(row.modes_payload_json)
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        ProfileAnalyticsGRDBProbe.logRead(
            viewer: key.viewerID,
            subject: key.subjectProfileID,
            revision: row.public_revision,
            elapsedMs: elapsed
        )
        return ProfileAnalyticsSnapshot(
            publicRevision: row.public_revision,
            fetchedAt: row.fetched_at,
            modeResults: modes,
            visibilityIdentity: row.visibility_identity
        )
    }

    func ingestProfileAnalyticsSnapshot(
        key: ProfileAnalyticsCacheKey,
        publicRevision: Int64,
        modeResults: [ProfileStatisticsMetrics.Mode: ProfileStatisticsMetrics.Result]
    ) async throws {
        let payload = try ProfileAnalyticsModesCodec.encode(modeResults)
        let started = Date()
        let record = ProfileAnalyticsSnapshotRecord(
            viewer_id: key.viewerID,
            subject_profile_id: key.subjectProfileID,
            contract_version: key.contractVersion,
            visibility_identity: key.visibilityIdentity,
            public_revision: publicRevision,
            fetched_at: ISO8601DateFormatter().string(from: Date()),
            modes_payload_json: payload
        )
        let queue = try await database.databaseQueue()
        try await queue.write { db in
            try record.insert(db, onConflict: .replace)
        }
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        ProfileAnalyticsGRDBProbe.logIngest(
            viewer: key.viewerID,
            subject: key.subjectProfileID,
            revision: publicRevision,
            elapsedMs: elapsed
        )
    }

    func deleteProfileAnalyticsSnapshots(
        viewerID: String,
        subjectProfileID: String? = nil
    ) async throws {
        let queue = try await database.databaseQueue()
        try await queue.write { db in
            var request = ProfileAnalyticsSnapshotRecord
                .filter(Column("viewer_id") == viewerID)
            if let subjectProfileID {
                request = request.filter(Column("subject_profile_id") == subjectProfileID)
            }
            try request.deleteAll(db)
        }
    }

    func deleteIncompatibleProfileAnalyticsSnapshots(
        viewerID: String,
        subjectProfileID: String,
        expectedVisibility: String
    ) async throws {
        let queue = try await database.databaseQueue()
        _ = try await queue.write { db in
            try ProfileAnalyticsSnapshotRecord
                .filter(Column("viewer_id") == viewerID)
                .filter(Column("subject_profile_id") == subjectProfileID)
                .filter(Column("visibility_identity") != expectedVisibility)
                .deleteAll(db)
        }
    }

    func profileAnalyticsCacheKey(
        viewerScopeID: String,
        subjectProfileID: ProfileID,
        visibility: ProfileAnalyticsVisibilityIdentity
    ) -> ProfileAnalyticsCacheKey {
        ProfileAnalyticsCacheKey(
            viewerID: viewerScopeID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            subjectProfileID: subjectProfileID.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            contractVersion: AnalyticsLocalSchema.profileAnalyticsContractVersion,
            visibilityIdentity: visibility.token
        )
    }
}
