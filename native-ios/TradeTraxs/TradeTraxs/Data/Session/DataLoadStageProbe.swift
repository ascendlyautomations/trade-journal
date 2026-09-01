import Foundation
import OSLog

#if DEBUG
/// Safe staged load tracing — one correlation ID per screen load.
nonisolated enum DataLoadStageProbe {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var sessions: [String: Session] = [:]

    struct Session: Sendable {
        var label: String
        var correlation: String
        var startedAt: Date
        var stages: [StageRecord] = []
    }

    struct StageRecord: Sendable, Equatable {
        var stage: String
        var elapsedMs: Int
        var detail: String?
    }

    private static let logger = Logger(
        subsystem: AppLog.subsystem,
        category: "DataLoadStage"
    )

    @discardableResult
    static func begin(_ label: String, correlation: String? = nil) -> String {
        let id = correlation ?? String(UUID().uuidString.prefix(8))
        lock.lock()
        sessions[id] = Session(label: label, correlation: id, startedAt: Date())
        lock.unlock()
        logger.debug("[\(id, privacy: .public)] BEGIN \(label, privacy: .public)")
        return id
    }

    static func trace(
        correlation: String,
        stage: String,
        detail: String? = nil
    ) {
        lock.lock()
        guard var session = sessions[correlation] else {
            lock.unlock()
            return
        }
        let elapsed = Int(Date().timeIntervalSince(session.startedAt) * 1_000)
        session.stages.append(StageRecord(stage: stage, elapsedMs: elapsed, detail: detail))
        sessions[correlation] = session
        lock.unlock()
        if let detail, !detail.isEmpty {
            logger.debug(
                "[\(correlation, privacy: .public)] \(session.label, privacy: .public) \(stage, privacy: .public) \(detail, privacy: .public) +\(elapsed)ms"
            )
        } else {
            logger.debug(
                "[\(correlation, privacy: .public)] \(session.label, privacy: .public) \(stage, privacy: .public) +\(elapsed)ms"
            )
        }
    }

    static func end(correlation: String, terminal: String) {
        trace(correlation: correlation, stage: terminal)
        lock.lock()
        sessions.removeValue(forKey: correlation)
        lock.unlock()
    }

    static func session(for correlation: String) -> Session? {
        lock.lock()
        defer { lock.unlock() }
        return sessions[correlation]
    }

    static func resetForTests() {
        lock.lock()
        sessions = [:]
        lock.unlock()
    }
}
#else
nonisolated enum DataLoadStageProbe {
    static func begin(_ label: String, correlation: String? = nil) -> String { "" }
    static func trace(correlation: String, stage: String, detail: String? = nil) {}
    static func end(correlation: String, terminal: String) {}
    static func resetForTests() {}
}
#endif
