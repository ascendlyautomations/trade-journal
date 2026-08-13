import XCTest
@testable import TradeTraxs

final class RepositoryRequestFlightTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        RepositoryRequestFlight.shared.invalidate()
        ProfileRequestFlight.shared.invalidate()
        SessionNetworkProbe.resetForTesting()
    }

    override func tearDown() async throws {
        RepositoryRequestFlight.shared.invalidate()
        ProfileRequestFlight.shared.invalidate()
        SessionNetworkProbe.resetForTesting()
        try await super.tearDown()
    }

    func testCoalesceSharesOneNetworkOperation() async throws {
        let key = "test.coalesce:\(UUID().uuidString)"
        var fetchCount = 0

        async let a: Int = RepositoryRequestFlight.shared.coalesce(
            key: key,
            resource: "test.coalesce"
        ) {
            fetchCount += 1
            try await Task.sleep(nanoseconds: 40_000_000)
            return 7
        }
        async let b: Int = RepositoryRequestFlight.shared.coalesce(
            key: key,
            resource: "test.coalesce"
        ) {
            fetchCount += 1
            try await Task.sleep(nanoseconds: 40_000_000)
            return 7
        }

        let (left, right) = try await (a, b)
        XCTAssertEqual(left, 7)
        XCTAssertEqual(right, 7)
        XCTAssertEqual(fetchCount, 1)
    }

    func testDifferentKeysDoNotCoalesce() async throws {
        var fetchCount = 0

        async let a: Int = RepositoryRequestFlight.shared.coalesce(
            key: "test.a",
            resource: "test.split"
        ) {
            fetchCount += 1
            try await Task.sleep(nanoseconds: 20_000_000)
            return 1
        }
        async let b: Int = RepositoryRequestFlight.shared.coalesce(
            key: "test.b",
            resource: "test.split"
        ) {
            fetchCount += 1
            try await Task.sleep(nanoseconds: 20_000_000)
            return 2
        }

        let (left, right) = try await (a, b)
        XCTAssertEqual(left, 1)
        XCTAssertEqual(right, 2)
        XCTAssertEqual(fetchCount, 2)
    }

    func testProfileFacadeStillCoalescesViaSharedFlight() async throws {
        let id = ProfileID("00000000-0000-4000-8000-000000000601")
        var fetchCount = 0
        let profile = Profile(
            id: id,
            userID: UserID(id.rawValue),
            username: "flight",
            displayName: "Flight",
            bio: nil,
            avatar: nil,
            traderType: .futures,
            tradingStyle: nil,
            primaryMarket: nil,
            startedTradingAt: nil,
            isPrivate: false,
            isCreator: false,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        async let a = ProfileRequestFlight.shared.profile(id: id) {
            fetchCount += 1
            try await Task.sleep(nanoseconds: 40_000_000)
            return profile
        }
        async let b = ProfileRequestFlight.shared.profile(id: id) {
            fetchCount += 1
            try await Task.sleep(nanoseconds: 40_000_000)
            return profile
        }
        _ = try await (a, b)
        XCTAssertEqual(fetchCount, 1)
    }

    func testOwnedTradesPublicAndPrivateKeysDiffer() async throws {
        // Documented key shape — public Profile list must not share a flight with owner Dashboard.
        let profileID = ProfileID("00000000-0000-4000-8000-000000000602")
        let publicKey =
            "trades.owned:\(profileID.rawValue):pub=true:acct=-:limit=500:cursor=-"
        let privateKey =
            "trades.owned:\(profileID.rawValue):pub=false:acct=-:limit=500:cursor=-"
        XCTAssertNotEqual(publicKey, privateKey)

        var publicFetches = 0
        var privateFetches = 0
        async let pub: Int = RepositoryRequestFlight.shared.coalesce(
            key: publicKey,
            resource: "trades.owned"
        ) {
            publicFetches += 1
            try await Task.sleep(nanoseconds: 20_000_000)
            return 1
        }
        async let priv: Int = RepositoryRequestFlight.shared.coalesce(
            key: privateKey,
            resource: "trades.owned"
        ) {
            privateFetches += 1
            try await Task.sleep(nanoseconds: 20_000_000)
            return 2
        }
        _ = try await (pub, priv)
        XCTAssertEqual(publicFetches, 1)
        XCTAssertEqual(privateFetches, 1)
    }
}
