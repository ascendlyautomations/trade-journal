import Foundation

/// Prevents stale async entity disk writes from overwriting newer mutations.
nonisolated enum SocialEntityWriteGeneration {
    private static let lock = NSLock()
    private static var tokenByKey: [String: UInt64] = [:]
    private static var nextToken: UInt64 = 0

    nonisolated static func bump(
        viewerID: ProfileID,
        kind: SocialEntityDiskCache.EntityKind,
        entityID: String
    ) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        nextToken += 1
        tokenByKey[storageKey(viewerID: viewerID, kind: kind, entityID: entityID)] = nextToken
        return nextToken
    }

    nonisolated static func isStale(
        viewerID: ProfileID,
        kind: SocialEntityDiskCache.EntityKind,
        entityID: String,
        generation: UInt64
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return tokenByKey[storageKey(viewerID: viewerID, kind: kind, entityID: entityID)] != generation
    }

    static func resetForTesting() {
        lock.lock()
        defer { lock.unlock() }
        tokenByKey = [:]
        nextToken = 0
    }

    private static func storageKey(
        viewerID: ProfileID,
        kind: SocialEntityDiskCache.EntityKind,
        entityID: String
    ) -> String {
        "\(viewerID.rawValue)|\(kind.rawValue)|\(entityID)"
    }
}
