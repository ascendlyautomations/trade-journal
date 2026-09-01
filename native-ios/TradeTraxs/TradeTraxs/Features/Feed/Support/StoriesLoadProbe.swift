import Foundation
import OSLog

#if DEBUG
/// Temporary DEBUG instrumentation to distinguish empty Supabase vs over-filtering vs UI.
nonisolated enum StoriesLoadProbe {
    private static let logger = Logger(subsystem: AppLog.subsystem, category: "StoriesLoad")
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _events: [(stage: String, detail: String)] = []

    static var events: [(stage: String, detail: String)] {
        lock.lock()
        defer { lock.unlock() }
        return _events
    }

    static func reset() {
        lock.lock()
        _events.removeAll()
        lock.unlock()
    }

    static func record(stage: String, detail: String) {
        lock.lock()
        _events.append((stage, detail))
        lock.unlock()
        logger.debug("stories[\(stage, privacy: .public)] \(detail, privacy: .public)")
        print("[StoriesLoad] \(stage): \(detail)")
    }

    static var summary: String {
        events.map { "\($0.stage)=\($0.detail)" }.joined(separator: " | ")
    }
}
#else
nonisolated enum StoriesLoadProbe {
    static var events: [(stage: String, detail: String)] { [] }
    static func reset() {}
    static func record(stage: String, detail: String) {}
    static var summary: String { "" }
}
#endif
