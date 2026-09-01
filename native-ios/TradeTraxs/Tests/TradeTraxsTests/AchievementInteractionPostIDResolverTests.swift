import XCTest
@testable import TradeTraxs

final class AchievementInteractionPostIDResolverTests: XCTestCase {
    override func setUp() async throws {
        await AchievementInteractionPostIDResolver.shared.resetCache()
    }

    func testResolvesAchievementIDToPostID() async throws {
        let database = StubAchievementPostDatabase(
            postsByID: ["post-1"],
            postIDByAchievementID: ["ach-1": "post-1"]
        )

        let resolved = try await AchievementInteractionPostIDResolver.shared.postID(
            for: "ach-1",
            database: database
        )

        XCTAssertEqual(resolved, "post-1")
        XCTAssertEqual(database.selectOneCallCount, 2)
    }

    func testLeavesFeedPostIDUnchanged() async throws {
        let database = StubAchievementPostDatabase(postsByID: ["post-9"])

        let resolved = try await AchievementInteractionPostIDResolver.shared.postID(
            for: "post-9",
            database: database
        )

        XCTAssertEqual(resolved, "post-9")
        XCTAssertEqual(database.selectOneCallCount, 1)
    }

    func testCachesResolvedPostID() async throws {
        let database = StubAchievementPostDatabase(
            postIDByAchievementID: ["ach-2": "post-2"]
        )

        _ = try await AchievementInteractionPostIDResolver.shared.postID(
            for: "ach-2",
            database: database
        )
        _ = try await AchievementInteractionPostIDResolver.shared.postID(
            for: "ach-2",
            database: database
        )

        XCTAssertEqual(database.selectOneCallCount, 2)
    }
}

private final class StubAchievementPostDatabase: SupabaseDatabaseExecuting, @unchecked Sendable {
    var postsByID: Set<String>
    var postIDByAchievementID: [String: String]
    private(set) var selectOneCallCount = 0

    init(
        postsByID: Set<String> = [],
        postIDByAchievementID: [String: String] = [:]
    ) {
        self.postsByID = postsByID
        self.postIDByAchievementID = postIDByAchievementID
    }

    var isConfigured: Bool { true }

    func select<T>(
        _ type: T.Type,
        from table: String,
        query: [URLQueryItem],
        headers: [String: String]
    ) async throws -> [T] where T: Decodable {
        []
    }

    func selectOne<T>(
        _ type: T.Type,
        from table: String,
        query: [URLQueryItem]
    ) async throws -> T where T: Decodable {
        selectOneCallCount += 1
        guard table == "achievement_posts" else {
            throw AppError.unknown(message: "unexpected table")
        }

        let postID: String?
        if query.contains(where: { $0.name == "id" && $0.value == "eq.post-9" }) {
            postID = "post-9"
        } else if query.contains(where: { $0.name == "id" && $0.value == "eq.post-1" }) {
            postID = "post-1"
        } else if let achievementEQ = query.first(where: { $0.name == "achievement_id" })?.value,
                  achievementEQ.hasPrefix("eq.") {
            let achievementID = String(achievementEQ.dropFirst(3))
            postID = postIDByAchievementID[achievementID]
        } else {
            postID = nil
        }

        guard let postID else {
            throw AppError.unknown(message: "missing row")
        }

        let payload = ["id": postID]
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func count(from table: String, query: [URLQueryItem]) async throws -> Int { 0 }

    func insert<Body, T>(
        _ body: Body,
        into table: String,
        query: [URLQueryItem],
        returning type: T.Type
    ) async throws -> T where Body: Encodable, T: Decodable {
        throw AppError.unknown(message: "not implemented")
    }

    func insert<Body>(_ body: Body, into table: String) async throws where Body: Encodable {
        throw AppError.unknown(message: "not implemented")
    }

    func update<Body, T>(
        _ body: Body,
        table: String,
        query: [URLQueryItem],
        returning type: T.Type
    ) async throws -> T where Body: Encodable, T: Decodable {
        throw AppError.unknown(message: "not implemented")
    }

    func update<Body>(_ body: Body, table: String, query: [URLQueryItem]) async throws where Body: Encodable {}

    func upsert<Body, T>(
        _ body: Body,
        into table: String,
        onConflict: String,
        returning type: T.Type,
        select: String
    ) async throws -> T where Body: Encodable, T: Decodable {
        throw AppError.unknown(message: "not implemented")
    }

    func delete(from table: String, query: [URLQueryItem]) async throws {}

    func rpcData(functionName: String, parametersJSON: Data?) async throws -> Data {
        throw AppError.unknown(message: "not implemented")
    }
}
