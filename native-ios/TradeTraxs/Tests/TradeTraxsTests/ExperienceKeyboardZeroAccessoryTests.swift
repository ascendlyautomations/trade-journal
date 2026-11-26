import XCTest
@testable import TradeTraxs

final class ExperienceKeyboardZeroAccessoryTests: XCTestCase {
    func testNoAccessoryTextViewIgnoresExternalAccessoryAssignment() {
        let textView = ExperienceNoKeyboardAccessoryTextView()
        XCTAssertIdentical(textView.inputAccessoryView, ExperienceKeyboardZeroAccessory.shared)
        textView.inputAccessoryView = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        XCTAssertIdentical(textView.inputAccessoryView, ExperienceKeyboardZeroAccessory.shared)
    }
}