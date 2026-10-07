import XCTest
@testable import TradeTraxs

final class KeyboardSafeBottomInsetTests: XCTestCase {
    func testLiftIsOnlyTheKeyboardOverlapMissingFromTheSafeArea() {
        XCTAssertEqual(
            KeyboardSafeBottomMath.additionalLift(keyboardCover: 336, safeAreaBottom: 34),
            302
        )
        XCTAssertEqual(
            KeyboardSafeBottomMath.additionalLift(keyboardCover: 360, safeAreaBottom: 320),
            40
        )
    }

    func testNoLiftWhenTheSafeAreaAlreadyClearsTheKeyboard() {
        XCTAssertEqual(
            KeyboardSafeBottomMath.additionalLift(keyboardCover: 336, safeAreaBottom: 336),
            0
        )
        XCTAssertEqual(
            KeyboardSafeBottomMath.additionalLift(keyboardCover: 34, safeAreaBottom: 34),
            0
        )
        XCTAssertEqual(
            KeyboardSafeBottomMath.additionalLift(keyboardCover: 0, safeAreaBottom: 34),
            0
        )
    }
}
