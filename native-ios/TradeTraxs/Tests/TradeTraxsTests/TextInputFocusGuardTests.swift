import UIKit
import XCTest
@testable import TradeTraxs

final class TextInputFocusGuardTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 390, height: 844)

    func testKeyboardStillOnScreenDoesNotClearFocus() {
        let notification = Notification(
            name: UIResponder.keyboardWillHideNotification,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: CGRect(x: 0, y: 500, width: 390, height: 344)
            ]
        )
        XCTAssertFalse(
            TextInputFocusGuard.shouldReleaseBoundFocus(
                onKeyboardWillHide: notification,
                textInputIsFirstResponder: false,
                screenBounds: screen
            )
        )
    }

    func testKeyboardOffScreenClearsFocusWhenNoTextInputIsActive() {
        let notification = Notification(
            name: UIResponder.keyboardWillHideNotification,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: CGRect(x: 0, y: 844, width: 390, height: 344)
            ]
        )
        XCTAssertTrue(
            TextInputFocusGuard.shouldReleaseBoundFocus(
                onKeyboardWillHide: notification,
                textInputIsFirstResponder: false,
                screenBounds: screen
            )
        )
    }

    func testActiveTextInputKeepsFocusWhileKeyboardHides() {
        let notification = Notification(
            name: UIResponder.keyboardWillHideNotification,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: CGRect(x: 0, y: 900, width: 390, height: 344)
            ]
        )
        XCTAssertFalse(
            TextInputFocusGuard.shouldReleaseBoundFocus(
                onKeyboardWillHide: notification,
                textInputIsFirstResponder: true,
                screenBounds: screen
            )
        )
    }

    func testTextFieldAndTextViewTouchesAreEditable() {
        let host = UIView()
        let field = UITextField()
        field.accessibilityIdentifier = "sample.field"
        let canvas = UIView()
        field.addSubview(canvas)
        host.addSubview(field)

        XCTAssertTrue(TextInputFocusGuard.touchIsInsideEditableView(canvas))
        XCTAssertEqual(TextInputFocusGuard.fieldIdentifier(for: canvas), "sample.field")

        let textView = UITextView()
        host.addSubview(textView)
        XCTAssertTrue(TextInputFocusGuard.touchIsInsideEditableView(textView))

        let label = UILabel()
        host.addSubview(label)
        XCTAssertFalse(TextInputFocusGuard.touchIsInsideEditableView(label))
    }
}
