import XCTest
@testable import TradeTraxs

final class BroadcastProgramVideoPresentationTests: XCTestCase {
    func testNoPlaceholderWhenVideoReady() {
        let result = BroadcastProgramVideoPresentation.resolvePlaceholder(
            showsProgramVideoSurface: true,
            isLive: true,
            hasDisplayableVideo: true,
            connection: .connected,
            isJoining: false,
            hostConnected: true,
            primaryMediaPublisherConnected: true,
            broadcastSourceIsObs: false,
            hasSubscribedProgramVideo: true,
            videoWasDisplayedBefore: false
        )
        XCTAssertNil(result)
    }

    func testPreparingStreamOnStartup() {
        let result = BroadcastProgramVideoPresentation.resolvePlaceholder(
            showsProgramVideoSurface: true,
            isLive: true,
            hasDisplayableVideo: false,
            connection: .connected,
            isJoining: false,
            hostConnected: true,
            primaryMediaPublisherConnected: nil,
            broadcastSourceIsObs: false,
            hasSubscribedProgramVideo: false,
            videoWasDisplayedBefore: false
        )
        XCTAssertEqual(result?.title, "Preparing Stream...")
        XCTAssertEqual(result?.showsSpinner, true)
    }

    func testWaitingForVideoAfterTrackLoss() {
        let result = BroadcastProgramVideoPresentation.resolvePlaceholder(
            showsProgramVideoSurface: true,
            isLive: true,
            hasDisplayableVideo: false,
            connection: .connected,
            isJoining: false,
            hostConnected: true,
            primaryMediaPublisherConnected: true,
            broadcastSourceIsObs: false,
            hasSubscribedProgramVideo: false,
            videoWasDisplayedBefore: true
        )
        XCTAssertEqual(result?.title, "Waiting for video…")
    }

    func testWaitingForBroadcasterWhenHostDisconnected() {
        let result = BroadcastProgramVideoPresentation.resolvePlaceholder(
            showsProgramVideoSurface: true,
            isLive: true,
            hasDisplayableVideo: false,
            connection: .connected,
            isJoining: false,
            hostConnected: false,
            primaryMediaPublisherConnected: false,
            broadcastSourceIsObs: false,
            hasSubscribedProgramVideo: false,
            videoWasDisplayedBefore: false
        )
        XCTAssertEqual(result?.title, "Waiting for broadcaster…")
    }

    func testObsIngressConnectedDoesNotWaitForHumanHost() {
        let result = BroadcastProgramVideoPresentation.resolvePlaceholder(
            showsProgramVideoSurface: true,
            isLive: true,
            hasDisplayableVideo: false,
            connection: .connected,
            isJoining: false,
            hostConnected: false,
            primaryMediaPublisherConnected: true,
            broadcastSourceIsObs: true,
            hasSubscribedProgramVideo: true,
            videoWasDisplayedBefore: false
        )
        XCTAssertEqual(result?.title, "Preparing Stream...")
    }

    func testObsWaitsWhenNeitherHostNorIngressConnected() {
        let result = BroadcastProgramVideoPresentation.resolvePlaceholder(
            showsProgramVideoSurface: true,
            isLive: true,
            hasDisplayableVideo: false,
            connection: .connected,
            isJoining: false,
            hostConnected: false,
            primaryMediaPublisherConnected: false,
            broadcastSourceIsObs: true,
            hasSubscribedProgramVideo: false,
            videoWasDisplayedBefore: false
        )
        XCTAssertEqual(result?.title, "Waiting for broadcaster…")
    }
}