import Foundation

#if DEBUG
/// Correlated per-image DEBUG timeline — one request, one printable story.
nonisolated enum FeedImageTimingTrace {
    struct Session: Sendable {
        var correlationID: UUID
        var mediaID: String
        var cacheKey: String
        var surface: String
        var deliveryQuality: String
        var createdAt: CFAbsoluteTime
        var events: [(name: String, elapsedMs: Double, detail: String?)] = []
    }

    private static let lock = NSLock()
    private static var sessions: [UUID: Session] = [:]

    nonisolated static func begin(
        mediaID: String,
        cacheKey: String,
        surface: String,
        deliveryQuality: String
    ) -> UUID {
        let id = UUID()
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        sessions[id] = Session(
            correlationID: id,
            mediaID: mediaID,
            cacheKey: cacheKey,
            surface: surface,
            deliveryQuality: deliveryQuality,
            createdAt: now
        )
        lock.unlock()
        event(id, "request.created")
        return id
    }

    nonisolated static func event(_ correlationID: UUID, _ name: String, detail: String? = nil) {
        lock.lock()
        guard var session = sessions[correlationID] else {
            lock.unlock()
            return
        }
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - session.createdAt) * 1000
        session.events.append((name: name, elapsedMs: elapsedMs, detail: detail))
        sessions[correlationID] = session
        lock.unlock()
    }

    nonisolated static func complete(_ correlationID: UUID) {
        finish(correlationID, terminal: "request.completed")
    }

    nonisolated static func cancelled(_ correlationID: UUID) {
        finish(correlationID, terminal: "request.cancelled")
    }

    nonisolated static func failed(_ correlationID: UUID, message: String) {
        event(correlationID, "request.failed", detail: message)
        finish(correlationID, terminal: "request.failed")
    }

    private nonisolated static func finish(_ correlationID: UUID, terminal: String) {
        lock.lock()
        guard var session = sessions.removeValue(forKey: correlationID) else {
            lock.unlock()
            return
        }
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - session.createdAt) * 1000
        session.events.append((name: terminal, elapsedMs: elapsedMs, detail: nil))
        let timeline = session.events
            .map { event in
                let detail = event.detail.map { " \($0)" } ?? ""
                return "  +\(String(format: "%.1f", event.elapsedMs))ms \(event.name)\(detail)"
            }
            .joined(separator: "\n")
        lock.unlock()

        print(
            """
            [FeedImageTiming] correlation=\(correlationID.uuidString.prefix(8)) \
            mediaID=\(session.mediaID) surface=\(session.surface) \
            deliveryQuality=\(session.deliveryQuality) cacheKey=\(session.cacheKey)
            \(timeline)
            """
        )
    }

    nonisolated static func resetForTesting() {
        lock.lock()
        sessions.removeAll()
        lock.unlock()
    }
}
#else
nonisolated enum FeedImageTimingTrace {
    nonisolated static func begin(
        mediaID: String,
        cacheKey: String,
        surface: String,
        deliveryQuality: String
    ) -> UUID { UUID() }

    nonisolated static func event(_ correlationID: UUID, _ name: String, detail: String? = nil) {}
    nonisolated static func complete(_ correlationID: UUID) {}
    nonisolated static func cancelled(_ correlationID: UUID) {}
    nonisolated static func failed(_ correlationID: UUID, message: String) {}
    nonisolated static func resetForTesting() {}
}
#endif
