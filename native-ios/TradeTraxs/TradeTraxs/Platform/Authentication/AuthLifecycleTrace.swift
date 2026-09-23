import Foundation

#if DEBUG
nonisolated enum AuthLifecycleTrace {
    static func log(
        operation: String,
        authGeneration: UInt64? = nil,
        sessionGeneration: UInt64? = nil,
        phase: String? = nil,
        requestPath: String? = nil,
        requestOwnerGeneration: UInt64? = nil,
        decision: String? = nil,
        reason: String? = nil,
        cancelInitiatorGeneration: UInt64? = nil
    ) {
        var parts = ["[AuthLifecycle] operation=\(operation)"]
        if let authGeneration { parts.append("authGeneration=\(authGeneration)") }
        if let sessionGeneration { parts.append("sessionGeneration=\(sessionGeneration)") }
        if let phase { parts.append("phase=\(phase)") }
        if let requestPath { parts.append("requestPath=\(requestPath)") }
        if let requestOwnerGeneration { parts.append("requestOwnerGeneration=\(requestOwnerGeneration)") }
        if let decision { parts.append("decision=\(decision)") }
        if let reason { parts.append("reason=\(reason)") }
        if let cancelInitiatorGeneration {
            parts.append("cancelInitiatorGeneration=\(cancelInitiatorGeneration)")
        }
        print(parts.joined(separator: " "))
    }
}
#else
nonisolated enum AuthLifecycleTrace {
    static func log(
        operation: String,
        authGeneration: UInt64? = nil,
        sessionGeneration: UInt64? = nil,
        phase: String? = nil,
        requestPath: String? = nil,
        requestOwnerGeneration: UInt64? = nil,
        decision: String? = nil,
        reason: String? = nil,
        cancelInitiatorGeneration: UInt64? = nil
    ) {}
}
#endif

/// Monotonic auth lifecycle generation — readable from networking without MainActor.
nonisolated enum AuthLifecycleGeneration {
    private static let lock = NSLock()
    private static var value: UInt64 = 0

    static func current() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    @discardableResult
    static func bump() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        value &+= 1
        return value
    }

    static func resetForTesting() {
        lock.lock()
        defer { lock.unlock() }
        value = 0
    }
}
