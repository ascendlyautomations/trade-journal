import Foundation

#if DEBUG
enum LogoutTrace {
    private static var tapStartedAt: Date?

    static func tap(generation: UInt64) {
        tapStartedAt = Date()
        print("[LogoutTrace] tap generation=\(generation)")
    }

    static func generationInvalidated(elapsedMs: Int) {
        print("[LogoutTrace] generationInvalidated elapsedMs=\(elapsedMs)")
    }

    static func localSessionCleared(elapsedMs: Int) {
        print("[LogoutTrace] localSessionCleared elapsedMs=\(elapsedMs)")
    }

    static func loginPresented(elapsedMs: Int) {
        print("[LogoutTrace] loginPresented elapsedMs=\(elapsedMs)")
    }

    static func networkTasksCancelled(count: Int) {
        print("[LogoutTrace] networkTasksCancelled count=\(count)")
    }

    static func networkWaitersCancelled(count: Int) {
        print("[LogoutTrace] networkWaitersCancelled count=\(count)")
    }

    static func realtimeForceCleared(routes: Int) {
        print("[LogoutTrace] realtimeForceCleared routes=\(routes)")
    }

    static func pushUnregisterStarted(background: Bool) {
        print("[LogoutTrace] pushUnregisterStarted background=\(background)")
    }

    static func pushUnregisterCompleted(outcome: String) {
        print("[LogoutTrace] pushUnregisterCompleted outcome=\(outcome)")
    }

    static func remoteSupabaseLogoutStarted(background: Bool) {
        print("[LogoutTrace] remoteSupabaseLogoutStarted background=\(background)")
    }

    static func remoteSupabaseLogoutCompleted(outcome: String) {
        print("[LogoutTrace] remoteSupabaseLogoutCompleted outcome=\(outcome)")
    }

    static func staleResultRejected(domain: String, generation: UInt64) {
        print("[LogoutTrace] staleResultRejected domain=\(domain) generation=\(generation)")
    }

    static func elapsedSinceTapMs() -> Int {
        guard let tapStartedAt else { return -1 }
        return Int(Date().timeIntervalSince(tapStartedAt) * 1000)
    }
}
#else
enum LogoutTrace {
    static func tap(generation: UInt64) {}
    static func generationInvalidated(elapsedMs: Int) {}
    static func localSessionCleared(elapsedMs: Int) {}
    static func loginPresented(elapsedMs: Int) {}
    static func networkTasksCancelled(count: Int) {}
    static func networkWaitersCancelled(count: Int) {}
    static func realtimeForceCleared(routes: Int) {}
    static func pushUnregisterStarted(background: Bool) {}
    static func pushUnregisterCompleted(outcome: String) {}
    static func remoteSupabaseLogoutStarted(background: Bool) {}
    static func remoteSupabaseLogoutCompleted(outcome: String) {}
    static func staleResultRejected(domain: String, generation: UInt64) {}
    static func elapsedSinceTapMs() -> Int { -1 }
}
#endif
