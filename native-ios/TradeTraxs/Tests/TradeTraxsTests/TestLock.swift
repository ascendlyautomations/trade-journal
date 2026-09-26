import Foundation

/// Synchronous lock scope so async tests do not call `NSLock.lock()` directly.
enum TestLock {
    nonisolated static func withLock<T>(_ lock: NSLock, _ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
