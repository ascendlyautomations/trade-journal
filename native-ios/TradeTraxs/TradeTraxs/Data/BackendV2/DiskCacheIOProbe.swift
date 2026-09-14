import Foundation

#if DEBUG
/// Central DEBUG counter for persistent cache disk reads/writes.
nonisolated enum DiskCacheIOProbe {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var reads = 0
    nonisolated(unsafe) private static var writes = 0
    nonisolated(unsafe) private static var reconciliations = 0

    static func recordRead() {
        lock.lock()
        reads += 1
        lock.unlock()
    }

    static func recordWrite() {
        lock.lock()
        writes += 1
        lock.unlock()
    }

    static func noteReconciliation() {
        lock.lock()
        reconciliations += 1
        lock.unlock()
    }

    static func snapshot() -> (reads: Int, writes: Int, reconciliations: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (reads, writes, reconciliations)
    }

    static func resetForTesting() {
        lock.lock()
        reads = 0
        writes = 0
        reconciliations = 0
        lock.unlock()
    }
}
#else
nonisolated enum DiskCacheIOProbe {
    static func recordRead() {}
    static func recordWrite() {}
    static func noteReconciliation() {}
    static func snapshot() -> (reads: Int, writes: Int, reconciliations: Int) { (0, 0, 0) }
    static func resetForTesting() {}
}
#endif
