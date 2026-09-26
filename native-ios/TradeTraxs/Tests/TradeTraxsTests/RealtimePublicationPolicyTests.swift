import XCTest
@testable import TradeTraxs

@MainActor
final class RealtimePublicationPolicyTests: XCTestCase {
    func testIneffectiveLikeTablesAreDisabledAndNotPublicationCandidates() {
        for table in ["stories", "profile_post_likes", "achievement_post_likes"] {
            XCTAssertFalse(RealtimePublicationPolicy.shouldOpenPostgresChangesWatch(table: table))
            XCTAssertTrue(RealtimePublicationPolicy.postgresChangesDisabledTables.contains(table))
            XCTAssertFalse(RealtimePublicationPolicy.publicationCandidateTables.contains(table))
        }
    }

    func testPublishedSocialLikeTablesRemainEnabled() {
        for table in ["reel_likes", "trade_likes", "likes", "messages", "room_messages"] {
            XCTAssertTrue(RealtimePublicationPolicy.shouldOpenPostgresChangesWatch(table: table))
        }
    }

    func testPublicationCandidatesIncludeMessagingTables() {
        XCTAssertEqual(
            RealtimePublicationPolicy.publicationCandidateTables,
            Set(["conversation_member_preferences", "room_members"])
        )
        XCTAssertTrue(RealtimePublicationPolicy.shouldOpenPostgresChangesWatch(table: "conversation_member_preferences"))
        XCTAssertTrue(RealtimePublicationPolicy.shouldOpenPostgresChangesWatch(table: "room_members"))
    }

    func testReadCursorWatchesStillJoin() async {
        let provider = makeProvider()
        let userID = "viewer-phase3"

        let readWatch = provider.watchConversationReadCursors(
            userID: userID,
            accessToken: nil,
            debugOwner: "test"
        )
        let roomReadWatch = provider.watchRoomReadCursors(
            userID: userID,
            accessToken: nil,
            debugOwner: "test"
        )
        await settle()
        XCTAssertEqual(provider.testing_routeSnapshot(routeKey: "dm-read:\(userID)").consumerCount, 1)
        XCTAssertEqual(provider.testing_routeSnapshot(routeKey: "room-read:\(userID)").consumerCount, 1)

        await provider.releaseWatch(readWatch.consumer)
        await provider.releaseWatch(roomReadWatch.consumer)
        await settle()
        XCTAssertEqual(provider.testing_routeSnapshot(routeKey: "dm-read:\(userID)").consumerCount, 0)
        XCTAssertEqual(provider.testing_routeSnapshot(routeKey: "room-read:\(userID)").consumerCount, 0)
    }

    func testActivityNotificationsRouteJoinsForPublishedTable() async {
        let provider = makeProvider()
        let userID = "viewer-notifications"
        let routeKey = "notifications:\(userID)"

        let watch = provider.watchNotifications(userID: userID, accessToken: nil, debugOwner: "test")
        await settle()
        XCTAssertEqual(provider.testing_routeSnapshot(routeKey: routeKey).consumerCount, 1)
        await provider.releaseWatch(watch.consumer)
        await settle()
        XCTAssertEqual(provider.testing_routeSnapshot(routeKey: routeKey).consumerCount, 0)
    }

    // MARK: - Helpers

    private func makeProvider() -> LiveSupabaseRealtimeProvider {
        LiveSupabaseRealtimeProvider(
            configuration: AppConfiguration(
                buildConfiguration: .debug,
                apiBaseURL: nil,
                supabaseURL: URL(string: "https://example.supabase.co"),
                supabaseAnonKey: "anon",
                appDisplayName: "TradeTraxs"
            )
        )
    }

    private func settle() async {
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
}
