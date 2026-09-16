import SwiftUI
import UIKit

extension Notification.Name {
    /// Posted immediately before resigning first responder so bound ``FocusState`` can clear first.
    static let experienceKeyboardWillDismiss = Notification.Name("ExperienceKeyboard.willDismiss")
}

extension ExperienceKeyboard {
    /// Clears registered form focus (via ``View/experienceFormFocusSync(_:)``) and dismisses the keyboard.
    @MainActor
    static func dismissFormKeyboard() {
        NotificationCenter.default.post(name: .experienceKeyboardWillDismiss, object: nil)
        dismiss()
    }
}

// MARK: - Focus sync

private struct ExperienceFormFocusSyncOptionalModifier<F: Hashable>: ViewModifier {
    @FocusState.Binding var focus: F?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .experienceKeyboardWillDismiss)) { _ in
                focus = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                focus = nil
            }
    }
}

private struct ExperienceFormFocusSyncBoolModifier: ViewModifier {
    @FocusState.Binding var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .experienceKeyboardWillDismiss)) { _ in
                isFocused = false
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isFocused = false
            }
    }
}

extension View {
    /// Keeps ``FocusState`` in sync when the keyboard hides or the shared Done action runs.
    func experienceFormFocusSync<F: Hashable>(_ focus: FocusState<F?>.Binding) -> some View {
        modifier(ExperienceFormFocusSyncOptionalModifier(focus: focus))
    }

    /// Same as ``experienceFormFocusSync(_:)`` for non-optional ``FocusState<Bool>``.
    func experienceFormFocusSync(_ isFocused: FocusState<Bool>.Binding) -> some View {
        modifier(ExperienceFormFocusSyncBoolModifier(isFocused: isFocused))
    }

    /// Standard scroll keyboard dismissal for forms — does not force scrolling when content fits.
    func experienceFormScrollKeyboard() -> some View {
        scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
    }

    /// Form screens: sync focus and release the keyboard when navigating away.
    func experienceFormKeyboard<F: Hashable>(
        focus: FocusState<F?>.Binding,
        releaseOnDisappear: Bool = true
    ) -> some View {
        experienceFormFocusSync(focus)
            .modifier(
                ExperienceFormKeyboardDisappearModifier(
                    releaseOnDisappear: releaseOnDisappear
                )
            )
    }

    /// Form screens with boolean focus binding.
    func experienceFormKeyboard(
        isFocused: FocusState<Bool>.Binding,
        releaseOnDisappear: Bool = true
    ) -> some View {
        experienceFormFocusSync(isFocused)
            .modifier(
                ExperienceFormKeyboardDisappearModifier(
                    releaseOnDisappear: releaseOnDisappear
                )
            )
    }
}

private struct ExperienceFormKeyboardDisappearModifier: ViewModifier {
    let releaseOnDisappear: Bool

    func body(content: Content) -> some View {
        content.onDisappear {
            guard releaseOnDisappear else { return }
            ExperienceKeyboard.dismissFormKeyboard()
        }
    }
}
