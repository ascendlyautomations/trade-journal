import Foundation
import os
import OSLog

/// Signposts for main-thread freeze investigation (Instruments in DEBUG).
nonisolated enum MainThreadFreezeProbe {
    #if DEBUG
    private static let log = OSLog(subsystem: "com.tradetraxs.TradeTraxs", category: "MainThreadFreeze")

    static func begin(_ name: StaticString) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return id
    }

    static func end(_ name: StaticString, id: OSSignpostID) {
        os_signpost(.end, log: log, name: name, signpostID: id)
    }

    static func event(_ name: StaticString, _ detail: String = "") {
        os_signpost(.event, log: log, name: name, "%{public}s", detail)
    }

    static func measure<T>(_ name: StaticString, _ work: () throws -> T) rethrows -> T {
        let id = begin(name)
        defer { end(name, id: id) }
        return try work()
    }

    static func measureAsync<T>(_ name: StaticString, _ work: () async throws -> T) async rethrows -> T {
        let id = begin(name)
        defer { end(name, id: id) }
        return try await work()
    }
    #else
    static func begin(_ name: StaticString) -> UInt64 { 0 }
    static func end(_ name: StaticString, id: UInt64) {}
    static func event(_ name: StaticString, _ detail: String = "") {}
    static func measure<T>(_ name: StaticString, _ work: () throws -> T) rethrows -> T { try work() }
    static func measureAsync<T>(_ name: StaticString, _ work: () async throws -> T) async rethrows -> T {
        try await work()
    }
    #endif
}

/// Tracks nested MainActor operations for hang correlation.
@MainActor
enum MainThreadOperationTracker {
    private static var stack: [String] = []

    static var activeOperation: String {
        stack.isEmpty ? "idle" : stack.joined(separator: " > ")
    }

    static func push(_ operation: String) {
        stack.append(operation)
    }

    static func pop(_ operation: String) {
        if stack.last == operation {
            stack.removeLast()
        } else if let index = stack.lastIndex(of: operation) {
            stack.remove(at: index)
        }
    }

    static func track<T>(_ operation: String, _ work: () throws -> T) rethrows -> T {
        push(operation)
        defer { pop(operation) }
        return try work()
    }

    static func trackAsync<T>(_ operation: String, _ work: () async throws -> T) async rethrows -> T {
        push(operation)
        defer { pop(operation) }
        return try await work()
    }
}

/// Times synchronous MainActor work. SLOW (>50ms) lines always print on device builds.
@MainActor
enum MainThreadWorkProbe {
    private static let logger = Logger(
        subsystem: "com.tradetraxs.TradeTraxs",
        category: "MainThreadWork"
    )

    private static let slowThresholdMs = 50
    #if DEBUG
    private static let logThresholdMs = 16
    #else
    private static let logThresholdMs = 50
    #endif

    static func measure<T>(
        _ operation: String,
        surface: String? = nil,
        _ work: () throws -> T
    ) rethrows -> T {
        MainThreadOperationTracker.push(operation)
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            MainThreadOperationTracker.pop(operation)
            logIfNeeded(operation: operation, surface: surface, start: start)
        }
        return try work()
    }

    static func measureAsync<T>(
        _ operation: String,
        surface: String? = nil,
        _ work: () async throws -> T
    ) async rethrows -> T {
        MainThreadOperationTracker.push(operation)
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            MainThreadOperationTracker.pop(operation)
            logIfNeeded(operation: operation, surface: surface, start: start)
        }
        return try await work()
    }

    static func publish(surface: String, items: Int, durationMs: Int) {
        guard durationMs >= logThresholdMs else { return }
        let line =
            "[MainThreadWork] operation=\(surface).publish durationMs=\(durationMs) " +
            "mainThread=true items=\(items)"
        emit(line: line, operation: "\(surface).publish", durationMs: durationMs, surface: surface)
    }

    private static func logIfNeeded(operation: String, surface: String?, start: CFAbsoluteTime) {
        let durationMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        guard durationMs >= logThresholdMs else { return }
        let surfaceLabel = surface ?? "app"
        let line =
            "[MainThreadWork] operation=\(operation) durationMs=\(durationMs) " +
            "mainThread=true surface=\(surfaceLabel)"
        emit(line: line, operation: operation, durationMs: durationMs, surface: surfaceLabel)
    }

    private static func emit(line: String, operation: String, durationMs: Int, surface: String) {
        if durationMs >= slowThresholdMs {
            print("[MainThreadWork] SLOW operation=\(operation) durationMs=\(durationMs)")
            print(
                """
                [MainThreadHangContext] durationMs=\(durationMs) \
                surface=\(surface) operation=\(operation) \
                activeOperation=\(MainThreadOperationTracker.activeOperation)
                """
            )
        }
        #if DEBUG
        logger.debug("\(line, privacy: .public)")
        #else
        if durationMs >= slowThresholdMs {
            print(line)
        }
        #endif
    }
}
