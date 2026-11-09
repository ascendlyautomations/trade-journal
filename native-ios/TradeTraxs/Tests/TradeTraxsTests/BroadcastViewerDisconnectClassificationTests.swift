import XCTest
@testable import TradeTraxs

final class BroadcastViewerDisconnectClassificationTests: XCTestCase {
    private let session = "sess-obs-1"
    private let viewer = "viewer-uuid"

    private func decodeSnapshot(_ json: String) throws -> LiveKitBroadcastInteractiveStateResponse.Snapshot {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(
            LiveKitBroadcastInteractiveStateResponse.Snapshot.self,
            from: data
        )
    }

    func testNormalEndStreamEnded() {
        XCTAssertEqual(
            BroadcastViewerDisconnectClassification.classify(
                watchingSessionId: session,
                statusLive: false,
                statusSessionId: session,
                snapshot: nil,
                viewerUserId: viewer
            ),
            .streamEnded
        )
    }

    func testObsShutdownStreamEnded() {
        XCTAssertEqual(
            BroadcastViewerDisconnectClassification.classify(
                watchingSessionId: session,
                statusLive: false,
                statusSessionId: session,
                snapshot: nil,
                viewerUserId: viewer
            ),
            .streamEnded
        )
    }

    func testModeratorRemoval() throws {
        let snap = try decodeSnapshot(
            #"{"sessionId":"sess-obs-1","presentInLiveKitBroadcastRoom":false}"#
        )
        XCTAssertEqual(
            BroadcastViewerDisconnectClassification.classify(
                watchingSessionId: session,
                statusLive: true,
                statusSessionId: session,
                snapshot: snap,
                viewerUserId: viewer
            ),
            .removed(blocked: false)
        )
    }

    func testModeratorBlock() throws {
        let snap = try decodeSnapshot(
            #"{"sessionId":"sess-obs-1","blockedFromBroadcastRejoin":true,"presentInLiveKitBroadcastRoom":false}"#
        )
        XCTAssertEqual(
            BroadcastViewerDisconnectClassification.classify(
                watchingSessionId: session,
                statusLive: true,
                statusSessionId: session,
                snapshot: snap,
                viewerUserId: viewer
            ),
            .removed(blocked: true)
        )
    }

    func testNetworkDisconnectConnectionLost() throws {
        let snap = try decodeSnapshot(
            #"{"sessionId":"sess-obs-1","presentInLiveKitBroadcastRoom":true}"#
        )
        XCTAssertEqual(
            BroadcastViewerDisconnectClassification.classify(
                watchingSessionId: session,
                statusLive: true,
                statusSessionId: session,
                snapshot: snap,
                viewerUserId: viewer
            ),
            .connectionLost
        )
    }
}
