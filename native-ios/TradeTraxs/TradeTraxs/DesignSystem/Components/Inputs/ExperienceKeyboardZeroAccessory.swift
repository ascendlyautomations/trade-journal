import UIKit

/// Single zero-height accessory so hosts never show the system gray toolbar strip.
enum ExperienceKeyboardZeroAccessory {
    static let shared: UIView = {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
        view.isUserInteractionEnabled = false
        view.isHidden = true
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        return view
    }()
}

/// UITextView that refuses SwiftUI / UIKit keyboard accessory toolbars (story reply, DM-style).
final class ExperienceNoKeyboardAccessoryTextView: UITextView {
    override var inputAccessoryView: UIView? {
        get { ExperienceKeyboardZeroAccessory.shared }
        set { /* SwiftUI may attempt to assign a toolbar; ignore. */ }
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        reloadInputViews()
        return became
    }
}

@MainActor
enum ExperienceKeyboardAccessoryStrip {
    /// Strips `inputAccessoryView` on the active text input and reloads the keyboard.
    static func clearOnFirstResponderIfNeeded() {
        guard let responder = UIResponder.tradeTraxsCurrentFirstResponder else { return }
        if let field = responder as? UITextField {
            field.inputAccessoryView = ExperienceKeyboardZeroAccessory.shared
            field.reloadInputViews()
        } else if let textView = responder as? UITextView {
            textView.reloadInputViews()
        }
    }
}