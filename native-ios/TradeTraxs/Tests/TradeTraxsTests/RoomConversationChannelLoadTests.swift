import XCTest
@testable import TradeTraxs

@MainActor
final class RoomConversationChannelLoadTests: XCTestCase {
    func testLoadStateModelTracksTerminalStates() {
        XCTAssertTrue(RoomChannelThreadLoadState.loaded.isTerminal)
        XCTAssertTrue(RoomChannelThreadLoadState.loadedEmpty.isTerminal)
        XCTAssertFalse(RoomChannelThreadLoadState.loading.isTerminal)
        XCTAssertEqual(
            RoomChannelThreadLoadState(diskIsLoaded: true, messageCount: 0),
            .loadedEmpty
        )
        XCTAssertEqual(
            RoomChannelThreadLoadState(diskIsLoaded: false, messageCount: 3),
            .unloaded
        )
    }
}
