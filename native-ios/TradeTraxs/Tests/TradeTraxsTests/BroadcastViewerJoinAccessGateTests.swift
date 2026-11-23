import XCTest
@testable import TradeTraxs

final class BroadcastViewerJoinAccessGateTests: XCTestCase {
    private let viewer = "viewer-uuid"
    private let session = "sess-live-1"

    private func decodeSnapshot(_ json: String) throws -> LiveKitBroadcastInteractiveStateResponse.Snapshot {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(
            LiveKitBroadcastInteractiveStateResponse.Snapshot.self,
            from: data
        )
    }

    func testBlockedFromRejoinDeniesJoin() throws {
        let snap = try decodeSnapshot(
            #"{"sessionId":"sess-live-1","blockedFromBroadcastRejoin":true}"#
        )
        XCTAssertTrue(
            BroadcastViewerJoinAccessGate.isJoinDenied(
                snapshot: snap,
                activeSessionId: session,
                viewerUserId: viewer
            )
        )
    }

    func testSessionBlockListDeniesJoin() throws {
        let snap = try decodeSnapshot(
            #"{"sessionId":"sess-live-1","sessionBlocks":["viewer-uuid"]}"#
        )
        XCTAssertTrue(
            BroadcastViewerJoinAccessGate.isJoinDenied(
                snapshot: snap,
                activeSessionId: session,
                viewerUserId: viewer
            )
        )
    }

    func testRemovalWithoutBlockAllowsJoin() throws {
        let snap = try decodeSnapshot(
            #"{"sessionId":"sess-live-1","removedFromStream":true,"presentInLiveKitBroadcastRoom":false}"#
        )
        XCTAssertFalse(
            BroadcastViewerJoinAccessGate.isJoinDenied(
                snapshot: snap,
                activeSessionId: session,
                viewerUserId: viewer
            )
        )
    }

    func testDifferentSessionDoesNotDeny() throws {
        let snap = try decodeSnapshot(
            #"{"sessionId":"sess-next","blockedFromBroadcastRejoin":true}"#
        )
        XCTAssertFalse(
            BroadcastViewerJoinAccessGate.isJoinDenied(
                snapshot: snap,
                activeSessionId: session,
                viewerUserId: viewer
            )
        )
    }
}