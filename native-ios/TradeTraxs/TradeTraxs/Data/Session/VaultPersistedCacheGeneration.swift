import Foundation

enum VaultPersistedCacheGeneration {
    private static let lock = NSLock()
    private static var tokenByViewer: [String: UInt64] = [:]

    @MainActor
    static func bump(viewerID: ProfileID) -> UInt64 {
        let key = viewerID.rawValue
        lock.lock()
        let next = (tokenByViewer[key] ?? 0) + 1
        tokenByViewer[key] = next
        lock.unlock()
        return next
    }

    static func isStale(viewerID: ProfileID, generation: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return tokenByViewer[viewerID.rawValue] != generation
    }

    @MainActor
    static func resetForTesting() {
        tokenByViewer = [:]
    }
}
