import Foundation
import os.signpost

#if DEBUG
/// Structured cold-launch timing — no credentials or PII.
enum StartupTrace {
    nonisolated private static let lock = NSLock()
    nonisolated private static let signpostLog = OSLog(subsystem: "com.tradetraxs.TradeTraxs", category: "Startup")
    nonisolated(unsafe) private static var appStartTime: CFAbsoluteTime?
    nonisolated(unsafe) private static var activeSteps: [String: CFAbsoluteTime] = [:]
    nonisolated(unsafe) private static var signpostIDs: [String: OSSignpostID] = [:]

    nonisolated static func anchorAppStartIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        if appStartTime == nil {
            appStartTime = CFAbsoluteTimeGetCurrent()
            print("[StartupTrace] step=process event=begin mainThread=\(Thread.isMainThread) dtFromAppStartMs=0")
        }
    }

    nonisolated static func event(_ name: String) {
        print(
            "[StartupTrace] step=\(name) event=marker mainThread=\(Thread.isMainThread) dtFromAppStartMs=\(elapsedMs())"
        )
    }

    nonisolated static func begin(_ step: String) {
        lock.lock()
        appStartTime = appStartTime ?? CFAbsoluteTimeGetCurrent()
        activeSteps[step] = CFAbsoluteTimeGetCurrent()
        let signpostID = OSSignpostID(log: signpostLog)
        signpostIDs[step] = signpostID
        lock.unlock()
        os_signpost(.begin, log: signpostLog, name: "Startup", signpostID: signpostID, "%{public}s", step)
        print(
            "[StartupTrace] step=\(step) event=begin mainThread=\(Thread.isMainThread) dtFromAppStartMs=\(elapsedMs())"
        )
    }

    nonisolated static func end(_ step: String) {
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        let started = activeSteps.removeValue(forKey: step)
        let signpostID = signpostIDs.removeValue(forKey: step) ?? .exclusive
        lock.unlock()
        let durationMs: Int
        if let started {
            durationMs = Int((now - started) * 1_000)
        } else {
            durationMs = -1
        }
        os_signpost(.end, log: signpostLog, name: "Startup", signpostID: signpostID, "%{public}s", step)
        print(
            "[StartupTrace] step=\(step) event=end durationMs=\(durationMs) mainThread=\(Thread.isMainThread) dtFromAppStartMs=\(elapsedMs())"
        )
    }

    @discardableResult
    nonisolated static func measure<T>(_ step: String, _ work: () throws -> T) rethrows -> T {
        begin(step)
        defer { end(step) }
        return try work()
    }

    nonisolated private static func elapsedMs() -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard let appStartTime else { return 0 }
        return Int((CFAbsoluteTimeGetCurrent() - appStartTime) * 1_000)
    }
}
#else
enum StartupTrace {
    static func anchorAppStartIfNeeded() {}
    static func event(_ name: String) {}
    static func begin(_ name: String) {}
    static func end(_ name: String) {}
    @discardableResult
    static func measure<T>(_ step: String, _ work: () throws -> T) rethrows -> T {
        try work()
    }
}
#endif
