import Foundation

/// Prevents stale async following-disk writes from overwriting newer follow/unfollow mutations.
nonisolated enum RelationshipWriteGeneration {
    private static let lock = NSLock()
    private static var tokenByViewer: [String: UInt64] = [:]
    private static var nextToken: UInt64 = 0

    nonisolated static func bump(viewerID: ProfileID) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        nextToken += 1
        tokenByViewer[viewerID.rawValue] = nextToken
        return nextToken
    }

    nonisolated static func isStale(viewerID: ProfileID, generation: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return tokenByViewer[viewerID.rawValue] != generation
    }

    static func resetForTesting() {
        lock.lock()
        defer { lock.unlock() }
        tokenByViewer = [:]
        nextToken = 0
    }
}
