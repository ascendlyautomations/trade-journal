import Foundation
import UIKit

#if DEBUG
/// Passive DEBUG tracing for Login field focus / keyboard — no gestures, no credentials.
enum LoginFocusProbe {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var marks: [String: CFAbsoluteTime] = [:]

    static func focused(field: String) {
        mark("focus.\(field)")
        print("[LoginFocus] field=\(field) event=focused dtFromFocusMs=0")
    }

    static func firstCharacterChanged(field: String) {
        print(
            "[LoginFocus] field=\(field) event=firstCharacterChanged dtFromFocusMs=\(durationMs(since: "focus.\(field)") ?? 0)"
        )
    }

    static func keyboardWillShow() {
        mark("keyboardWillShow")
        let fromEmail = durationMs(since: "focus.email")
        let fromPassword = durationMs(since: "focus.password")
        let dtFromFocus = fromEmail ?? fromPassword
        print(
            "[LoginFocus] event=keyboardWillShow dtFromFocusMs=\(dtFromFocus.map(String.init) ?? "—")"
        )
    }

    static func keyboardDidShow() {
        mark("keyboardDidShow")
        let fromEmail = durationMs(since: "focus.email")
        let fromPassword = durationMs(since: "focus.password")
        let dtFromFocus = fromEmail ?? fromPassword
        let fromWillShow = durationMs(since: "keyboardWillShow")
        print(
            "[LoginFocus] event=keyboardDidShow dtFromFocusMs=\(dtFromFocus.map(String.init) ?? "—") dtFromKeyboardWillShowMs=\(fromWillShow.map(String.init) ?? "—")"
        )
    }

    static func installKeyboardObserversIfNeeded() {
        struct Token {
            static var installed = false
        }
        guard !Token.installed else { return }
        Token.installed = true
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { _ in keyboardWillShow() }
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardDidShowNotification,
            object: nil,
            queue: .main
        ) { _ in keyboardDidShow() }
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
}
#else
enum LoginFocusProbe {
    static func focused(field: String) {}
    static func firstCharacterChanged(field: String) {}
    static func installKeyboardObserversIfNeeded() {}
}
#endif
