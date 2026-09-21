import Foundation
import GRDB
import Testing
@testable import TradeTraxs

struct ProfileAnalyticsGRDBTests {
    @Test("Profile analytics schema migration creates snapshot table")
    func schemaMigration() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("profile-analytics-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let db = AnalyticsDatabase(configuration: .testing(databaseURL: url))
        _ = try await db.databaseQueue()
        let queue = try await db.databaseQueue()
        let exists = try await queue.read { db in
            try Bool.fetchOne(
                db,
                sql: """
                SELECT COUNT(*) > 0 FROM sqlite_master
                WHERE type='table' AND name='profile_analytics_snapshot'
                """
            )
        }
        #expect(exists == true)
    }

    @Test("Snapshot write/read round trip with viewer isolation")
    func snapshotRoundTrip() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("profile-analytics-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let database = AnalyticsDatabase(configuration: .testing(databaseURL: url))
        let store = AnalyticsLocalStore(database: database)
        let sample = ProfileAnalyticsV2Fixtures.sampleResult(tradeCount: 2, equity: 50)
        let keyA = store.profileAnalyticsCacheKey(
            viewerScopeID: "viewer-a",
            subjectProfileID: ProfileID("subject-1"),
            visibility: ProfileAnalyticsVisibilityIdentity(token: "public|subject-1|viewer|canView|notFollowing|public")
        )
        try await store.ingestProfileAnalyticsSnapshot(
            key: keyA,
            publicRevision: 4,
            modeResults: [.all: sample]
        )
        let read = try await store.readProfileAnalyticsSnapshot(key: keyA)
        #expect(read?.publicRevision == 4)
        #expect(read?.modeResults[.all]?.filteredTradeCount == 2)

        let keyOtherViewer = store.profileAnalyticsCacheKey(
            viewerScopeID: "viewer-b",
            subjectProfileID: ProfileID("subject-1"),
            visibility: ProfileAnalyticsVisibilityIdentity(token: "public|subject-1|viewer|canView|notFollowing|public")
        )
        let miss = try await store.readProfileAnalyticsSnapshot(key: keyOtherViewer)
        #expect(miss == nil)
    }

    @Test("Visibility mismatch deletes incompatible rows")
    func visibilityReject() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("profile-analytics-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = AnalyticsLocalStore(database: AnalyticsDatabase(configuration: .testing(databaseURL: url)))
        let subject = ProfileID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        let oldVisibility = ProfileAnalyticsVisibilityIdentity(token: "following|old")
        let newVisibility = ProfileAnalyticsVisibilityIdentity(token: "following|new")
        let keyOld = store.profileAnalyticsCacheKey(
            viewerScopeID: "viewer",
            subjectProfileID: subject,
            visibility: oldVisibility
        )
        try await store.ingestProfileAnalyticsSnapshot(
            key: keyOld,
            publicRevision: 1,
            modeResults: [.all: ProfileAnalyticsV2Fixtures.sampleResult(tradeCount: 1, equity: 1)]
        )
        try await store.deleteIncompatibleProfileAnalyticsSnapshots(
            viewerID: keyOld.viewerID,
            subjectProfileID: keyOld.subjectProfileID,
            expectedVisibility: newVisibility.token
        )
        let readOld = try await store.readProfileAnalyticsSnapshot(key: keyOld)
        #expect(readOld == nil)
        let keyNew = store.profileAnalyticsCacheKey(
            viewerScopeID: "viewer",
            subjectProfileID: subject,
            visibility: newVisibility
        )
        try await store.ingestProfileAnalyticsSnapshot(
            key: keyNew,
            publicRevision: 2,
            modeResults: [.all: ProfileAnalyticsV2Fixtures.sampleResult(tradeCount: 2, equity: 2)]
        )
        let readNew = try await store.readProfileAnalyticsSnapshot(key: keyNew)
        #expect(readNew?.publicRevision == 2)
    }

    @Test("Modes codec round trip preserves trade count")
    func modesCodec() throws {
        let sample = ProfileAnalyticsV2Fixtures.sampleResult(tradeCount: 5, equity: 10)
        let data = try ProfileAnalyticsModesCodec.encode([.all: sample])
        let decoded = try ProfileAnalyticsModesCodec.decode(data)
        #expect(decoded[.all]?.filteredTradeCount == 5)
    }

    @Test("GRDB session rejects stale subject after navigation")
    func staleSubject() async {
        await ProfileAnalyticsGRDBSession.shared.reset()
        await ProfileAnalyticsGRDBSession.shared.setActiveSubjectProfile("profile-b")
        #expect(await ProfileAnalyticsGRDBSession.shared.isActiveSubjectProfile("profile-a") == false)
    }

    @Test("Public mutation invalidation detects visibility toggle")
    func publicMutationDetection() {
        let owner = ProfileID("owner-id")
        let samples = ProfileTradeFixtures.samples(owner: owner)
        guard var publicTrade = samples.first(where: { $0.visibility == .public }) else {
            Issue.record("Missing public fixture trade")
            return
        }
        #expect(ProfileAnalyticsOwnerInvalidation.affectsPublicProfileAnalytics(old: nil, new: publicTrade))
        publicTrade.visibility = .private
        let original = samples.first(where: { $0.visibility == .public }) ?? publicTrade
        var restored = original
        restored.visibility = .public
        #expect(
            ProfileAnalyticsOwnerInvalidation.affectsPublicProfileAnalytics(
                old: restored,
                new: publicTrade
            )
        )
    }
}
