import Foundation

#if DEBUG
/// DEBUG timing for logged-out cold launch — no credentials or tokens.
enum UnauthLaunchProbe {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var appStartTime: CFAbsoluteTime?
    nonisolated(unsafe) private static var loginPresentedTime: CFAbsoluteTime?
    nonisolated(unsafe) private static var responsiveCheckScheduled = false

    static func recordAppStart() {
        lock.lock()
        appStartTime = CFAbsoluteTimeGetCurrent()
        lock.unlock()
        print("[UnauthLaunch] event=appStart")
    }

    static func sessionCheckStarted() {
        print("[UnauthLaunch] event=sessionCheckStarted dtFromAppStartMs=\(elapsedMs())")
    }

    static func noSession() {
        print("[UnauthLaunch] event=noSession dtFromAppStartMs=\(elapsedMs())")
    }

    static func loginFirstFramePresented() {
        lock.lock()
        loginPresentedTime = CFAbsoluteTimeGetCurrent()
        lock.unlock()
        print("[StartupTrace] event=loginFirstFramePresented dtFromAppStartMs=\(elapsedMs())")
        print("[UnauthLaunch] event=loginPresented dtFromAppStartMs=\(elapsedMs())")
        scheduleMainThreadResponsiveCheckIfNeeded()
    }

    /// Legacy alias — prefer ``loginFirstFramePresented()``.
    static func loginPresented() {
        loginFirstFramePresented()
    }

    static func loginInteractive() {
        print("[UnauthLaunch] event=loginInteractive dtFromAppStartMs=\(elapsedMs())")
    }

    static func mainThreadSlow(operation: String, durationMs: Int) {
        guard durationMs >= 50 else { return }
        print(
            "[UnauthLaunch] event=mainThreadSlow operation=\(operation) durationMs=\(durationMs) dtFromAppStartMs=\(elapsedMs())"
        )
    }

    private static func scheduleMainThreadResponsiveCheckIfNeeded() {
        lock.lock()
        guard !responsiveCheckScheduled else {
            lock.unlock()
            return
        }
        responsiveCheckScheduled = true
        lock.unlock()

        DispatchQueue.main.async {
            print(
                "[StartupTrace] event=loginMainThreadResponsive dtFromAppStartMs=\(elapsedMs()) dtFromLoginPresentedMs=\(elapsedSinceLoginPresentedMs())"
            )
            print("[UnauthLaunch] event=loginInteractive dtFromAppStartMs=\(elapsedMs())")
        }
    }

    private static func elapsedMs() -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard let appStartTime else { return 0 }
        return Int((CFAbsoluteTimeGetCurrent() - appStartTime) * 1_000)
    }

    private static func elapsedSinceLoginPresentedMs() -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard let loginPresentedTime else { return 0 }
        return Int((CFAbsoluteTimeGetCurrent() - loginPresentedTime) * 1_000)
    }
}
#else
enum UnauthLaunchProbe {
    static func recordAppStart() {}
    static func sessionCheckStarted() {}
    static func noSession() {}
    static func loginFirstFramePresented() {}
    static func loginPresented() {}
    static func loginInteractive() {}
    static func mainThreadSlow(operation: String, durationMs: Int) {}
}
#endif
