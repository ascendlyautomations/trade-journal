import SwiftUI
import UIKit

/// Shared keyboard dismissal helpers for pad keyboards (no Return / Done key).
enum ExperienceKeyboard {
    /// Resigns first responder — dismisses the keyboard without submitting forms.
    @MainActor
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

/// Trailing **Done** accessory on the system keyboard toolbar.
///
/// Attach at the screen / form level for any view that hosts
/// `.numberPad`, `.decimalPad`, `.phonePad`, or `.asciiCapableNumberPad`.
/// Does not change Return / Next / Send / Search on standard text keyboards.
private struct ExperienceKeyboardDoneToolbarModifier: ViewModifier {
    @Environment(\.themeColors) private var colors

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer(minLength: 0)
                Button("Done") {
                    ExperienceKeyboard.dismiss()
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(colors.accent)
                .accessibilityLabel("Done")
                .accessibilityHint("Dismisses the keyboard")
                .accessibilityIdentifier("keyboard.done")
            }
        }
    }
}

extension View {
    /// Adds a native keyboard accessory with a trailing Done button that resigns first responder.
    func experienceKeyboardDoneToolbar() -> some View {
        modifier(ExperienceKeyboardDoneToolbarModifier())
    }
}
