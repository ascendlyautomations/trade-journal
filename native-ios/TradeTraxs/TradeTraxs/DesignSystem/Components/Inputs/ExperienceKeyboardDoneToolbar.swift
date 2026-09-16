import SwiftUI
import UIKit

/// Shared keyboard dismissal helpers for pad keyboards (no Return / Done key).
///
/// - Tap outside: ``View/experienceKeyboardDismissOnTapOutside()``
/// - Form focus + lifecycle: ``View/experienceFormKeyboard(focus:releaseOnDisappear:)`` in ``ExperienceFormKeyboard.swift``
/// - Done toolbar: ``View/experienceKeyboardDoneToolbar()`` (calls ``ExperienceKeyboard/dismissFormKeyboard()``)
enum ExperienceKeyboard {
    /// Resigns first responder only. Prefer ``dismissFormKeyboard()`` when clearing ``FocusState``.
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
                    ExperienceKeyboard.dismissFormKeyboard()
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

    /// Leading **+/−** on the keyboard for signed decimal fields (use with `.decimalPad`).
    func experienceSignedDecimalKeyboardSignToggle(
        isActive: Bool,
        onToggleSign: @escaping () -> Void
    ) -> some View {
        modifier(
            ExperienceSignedDecimalKeyboardSignToggleModifier(
                isActive: isActive,
                onToggleSign: onToggleSign
            )
        )
    }
}

private struct ExperienceSignedDecimalKeyboardSignToggleModifier: ViewModifier {
    let isActive: Bool
    let onToggleSign: () -> Void

    @Environment(\.themeColors) private var colors

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if isActive {
                    Button("+/−") {
                        ExperienceHaptics.play(.selection)
                        onToggleSign()
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(colors.accent)
                    .accessibilityLabel("Toggle plus or minus")
                    .accessibilityIdentifier("keyboard.toggleSign")
                }
            }
        }
    }
}
