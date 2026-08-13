import Foundation
import OSLog

/// DEBUG-only Dashboard startup instrumentation.
///
/// Records a request/operation waterfall for cold Dashboard loads.
/// No-ops in Release. Tests may call ``beginSession`` / ``snapshot`` directly.
enum DashboardLoadProbe {
    struct Operation: Sendable, Equatable {
        var name: String
        var kind: Kind
        var startMs: Int
        var endMs: Int
        var durationMs: Int
        var rowCount: Int?
        var blocksFirstUsefulRender: Bool
        var note: String?

        enum Kind: String, Sendable {
            case network
            case cache
            case local
            case realtime
        }
    }

    struct SessionSnapshot: Sendable {
        var operations: [Operation]
        var firstUsefulRenderMs: Int?
        var fullHydrationMs: Int?
        var networkOperationCount: Int
        var blockingNetworkCount: Int
        var notificationRowsLoaded: Int
    }

    private static let lock = NSLock()
    private static var sessionStart: Date?
    private static var operations: [Operation] = []
    private static var firstUsefulRenderMs: Int?
    private static var fullHydrationMs: Int?
    private static var notificationRowsLoaded = 0
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "TradeTraxs",
        category: "DashboardLoad"
    )

    static func beginSession(label: String = "dashboard.cold") {
        #if DEBUG
        lock.lock()
        sessionStart = Date()
        operations = []
        firstUsefulRenderMs = nil
        fullHydrationMs = nil
        notificationRowsLoaded = 0
        lock.unlock()
        logger.debug("BEGIN \(label, privacy: .public)")
        #else
        _ = label
        #endif
    }

    static func markFirstUsefulRender() {
        #if DEBUG
        lock.lock()
        defer { lock.unlock() }
        guard firstUsefulRenderMs == nil, let start = sessionStart else { return }
        firstUsefulRenderMs = Int(Date().timeIntervalSince(start) * 1_000)
        logger.debug("FIRST_USEFUL_RENDER \(self.firstUsefulRenderMs ?? -1)ms")
        #endif
    }

    static func markFullHydration() {
        #if DEBUG
        lock.lock()
        defer { lock.unlock() }
        guard let start = sessionStart else { return }
        fullHydrationMs = Int(Date().timeIntervalSince(start) * 1_000)
        logger.debug("FULL_HYDRATION \(self.fullHydrationMs ?? -1)ms")
        #endif
    }

    static func recordNotificationRows(_ count: Int) {
        #if DEBUG
        lock.lock()
        notificationRowsLoaded += count
        lock.unlock()
        #else
        _ = count
        #endif
    }

    @discardableResult
    static func measure<T>(
        _ name: String,
        kind: Operation.Kind,
        blocksFirstUsefulRender: Bool,
        rowCount: Int? = nil,
        note: String? = nil,
        work: () async throws -> T
    ) async rethrows -> T {
        #if DEBUG
        let start = Date()
        let startMs = elapsedMs(from: start)
        do {
            let result = try await work()
            finish(
                name: name,
                kind: kind,
                startMs: startMs,
                end: Date(),
                blocksFirstUsefulRender: blocksFirstUsefulRender,
                rowCount: rowCount,
                note: note
            )
            return result
        } catch {
            finish(
                name: name,
                kind: kind,
                startMs: startMs,
                end: Date(),
                blocksFirstUsefulRender: blocksFirstUsefulRender,
                rowCount: rowCount,
                note: note.map { "\($0); error" } ?? "error"
            )
            throw error
        }
        #else
        return try await work()
        #endif
    }

    static func snapshot() -> SessionSnapshot {
        lock.lock()
        defer { lock.unlock() }
        let network = operations.filter { $0.kind == .network }
        return SessionSnapshot(
            operations: operations,
            firstUsefulRenderMs: firstUsefulRenderMs,
            fullHydrationMs: fullHydrationMs,
            networkOperationCount: network.count,
            blockingNetworkCount: network.filter(\.blocksFirstUsefulRender).count,
            notificationRowsLoaded: notificationRowsLoaded
        )
    }

    static func resetForTesting() {
        lock.lock()
        sessionStart = nil
        operations = []
        firstUsefulRenderMs = nil
        fullHydrationMs = nil
        notificationRowsLoaded = 0
        lock.unlock()
    }

    // MARK: - Private

    private static func elapsedMs(from date: Date) -> Int {
        lock.lock()
        let start = sessionStart ?? date
        lock.unlock()
        return Int(date.timeIntervalSince(start) * 1_000)
    }

    private static func finish(
        name: String,
        kind: Operation.Kind,
        startMs: Int,
        end: Date,
        blocksFirstUsefulRender: Bool,
        rowCount: Int?,
        note: String?
    ) {
        let endMs = elapsedMs(from: end)
        let op = Operation(
            name: name,
            kind: kind,
            startMs: startMs,
            endMs: endMs,
            durationMs: max(0, endMs - startMs),
            rowCount: rowCount,
            blocksFirstUsefulRender: blocksFirstUsefulRender,
            note: note
        )
        lock.lock()
        operations.append(op)
        lock.unlock()
        #if DEBUG
        let rows = rowCount.map(String.init) ?? "-"
        let block = blocksFirstUsefulRender ? "blocking" : "deferred"
        logger.debug(
            "\(startMs)ms…\(endMs)ms (\(op.durationMs)ms) \(name, privacy: .public) [\(kind.rawValue, privacy: .public)/\(block, privacy: .public)] rows=\(rows, privacy: .public)"
        )
        #endif
    }
}
