import Foundation
import SwiftUI
import UIKit

/// Decides whether a keyboard-hide notification may clear a bound `FocusState`.
enum TextInputFocusGuard {
    /// A hide that still leaves a text input first responder, or keeps the keyboard on screen, must not clear focus.
    static func shouldReleaseBoundFocus(
        onKeyboardWillHide notification: Notification,
        textInputIsFirstResponder: Bool,
        screenBounds: CGRect?
    ) -> Bool {
        if textInputIsFirstResponder { return false }
        return keyboardFrameIsOffscreen(notification, in: screenBounds)
    }

    static func shouldReleaseBoundFocus(onKeyboardWillHide notification: Notification) -> Bool {
        shouldReleaseBoundFocus(
            onKeyboardWillHide: notification,
            textInputIsFirstResponder: textInputIsFirstResponder(),
            screenBounds: activeWindow()?.bounds
        )
    }

    static func textInputIsFirstResponder() -> Bool {
        guard let responder = firstResponder(in: activeWindow()) else { return false }
        return isEditableInput(responder)
    }

    static func keyboardFrameIsOffscreen(_ notification: Notification, in bounds: CGRect?) -> Bool {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let bounds
        else { return true }
        return !frame.intersects(bounds)
    }

    static func touchIsInsideEditableView(_ view: UIView?) -> Bool {
        var current = view
        while let candidate = current {
            if isEditableInput(candidate) { return true }
            current = candidate.superview
        }
        return false
    }

    static func fieldIdentifier(for view: UIView?) -> String {
        var current = view
        while let candidate = current {
            if let identifier = candidate.accessibilityIdentifier, !identifier.isEmpty {
                return identifier
            }
            current = candidate.superview
        }
        return "unidentified"
    }

    static func isEditableInput(_ view: UIView) -> Bool {
        if view is UITextField || view is UITextView { return true }
        let name = NSStringFromClass(type(of: view))
        return name.contains("TextField")
            || name.contains("TextView")
            || name.contains("TextEditor")
            || name.contains("TextLayout")
    }

    private static func activeWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    private static func firstResponder(in view: UIView?) -> UIView? {
        guard let view else { return nil }
        if view.isFirstResponder { return view }
        for child in view.subviews {
            if let found = firstResponder(in: child) { return found }
        }
        return nil
    }
}

private struct TextInputProbeModifier: ViewModifier {
    let screen: String
    let field: String
    let text: String
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .onAppear {
                TextInputResponsivenessProbe.installKeyboardObserversIfNeeded()
            }
            .onChange(of: isFocused) { _, focused in
                if focused {
                    TextInputResponsivenessProbe.focusRequested(screen: screen, field: field)
                }
                TextInputResponsivenessProbe.focusChanged(
                    screen: screen,
                    field: field,
                    focused: focused
                )
            }
            .onChange(of: text) { old, new in
                guard old.isEmpty, !new.isEmpty else { return }
                TextInputResponsivenessProbe.firstCharacterChanged(screen: screen, field: field)
            }
    }
}

extension View {
    /// DEBUG timing for a local text field. Does not log the entered text.
    func experienceTextInputProbe(
        screen: String,
        field: String,
        text: String,
        isFocused: Bool
    ) -> some View {
        modifier(
            TextInputProbeModifier(
                screen: screen,
                field: field,
                text: text,
                isFocused: isFocused
            )
        )
    }
}

#if DEBUG
/// DEBUG timing for tap → focus → keyboard → first character. Never logs field contents.
enum TextInputResponsivenessProbe {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var marks: [String: CFAbsoluteTime] = [:]
    nonisolated(unsafe) private static var observersInstalled = false
    nonisolated(unsafe) private static var sawCharacter: Set<String> = []

    static func tap(screen: String, field: String) {
        let key = markKey(screen: screen, field: field)
        mark(key)
        log(event: "textInput.tap", screen: screen, field: field, elapsedMs: 0)
    }

    static func focusRequested(screen: String, field: String) {
        let key = markKey(screen: screen, field: field)
        if marks[key] == nil {
            mark(key)
        }
        log(
            event: "textInput.focusRequested",
            screen: screen,
            field: field,
            elapsedMs: durationMs(since: key) ?? 0
        )
    }

    static func focusChanged(screen: String, field: String, focused: Bool) {
        let key = markKey(screen: screen, field: field)
        if focused {
            sawCharacter.remove(key)
            if marks[key] == nil { mark(key) }
        }
        log(
            event: "textInput.focusChanged",
            screen: screen,
            field: field,
            elapsedMs: durationMs(since: key) ?? 0,
            extra: "focused=\(focused)"
        )
    }

    static func firstCharacterChanged(screen: String, field: String) {
        let key = markKey(screen: screen, field: field)
        guard sawCharacter.insert(key).inserted else { return }
        log(
            event: "textInput.firstCharacterChanged",
            screen: screen,
            field: field,
            elapsedMs: durationMs(since: key) ?? 0
        )
    }

    static func installKeyboardObserversIfNeeded() {
        guard !observersInstalled else { return }
        observersInstalled = true
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { _ in keyboard(event: "keyboardWillShow") }
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardDidShowNotification,
            object: nil,
            queue: .main
        ) { _ in keyboard(event: "keyboardDidShow") }
    }

    private static func keyboard(event: String) {
        let elapsed = durationMsSinceNewestMark() ?? 0
        log(event: event, screen: "keyboard", field: "—", elapsedMs: elapsed)
    }

    private static func log(
        event: String,
        screen: String,
        field: String,
        elapsedMs: Int,
        extra: String? = nil
    ) {
        let suffix = extra.map { " \($0)" } ?? ""
        print(
            "[TextInput] event=\(event) screen=\(screen) field=\(field) elapsedMs=\(elapsedMs) mainThread=\(Thread.isMainThread) bootstrapLoading=\(bootstrapIsLoading())\(suffix)"
        )
    }

    private static func bootstrapIsLoading() -> Bool {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                AppLaunchController.shared.deferredProductionBootstrapAvailable
            }
        }
        return false
    }

    private static func markKey(screen: String, field: String) -> String {
        "\(screen).\(field)"
    }

    private static func mark(_ key: String) {
        lock.lock()
        marks[key] = CFAbsoluteTimeGetCurrent()
        lock.unlock()
    }

    private static func durationMs(since key: String) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        guard let start = marks[key] else { return nil }
        return Int((CFAbsoluteTimeGetCurrent() - start) * 1_000)
    }

    private static func durationMsSinceNewestMark() -> Int? {
        lock.lock()
        defer { lock.unlock() }
        guard let start = marks.values.max() else { return nil }
        return Int((CFAbsoluteTimeGetCurrent() - start) * 1_000)
    }
}
#else
enum TextInputResponsivenessProbe {
    static func tap(screen: String, field: String) {}
    static func focusRequested(screen: String, field: String) {}
    static func focusChanged(screen: String, field: String, focused: Bool) {}
    static func firstCharacterChanged(screen: String, field: String) {}
    static func installKeyboardObserversIfNeeded() {}
}
#endif
