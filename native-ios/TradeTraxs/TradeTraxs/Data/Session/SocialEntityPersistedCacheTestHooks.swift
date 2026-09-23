import Foundation

nonisolated enum SocialEntityPersistedCacheTestHooks {
    private static let lock = NSLock()
    private static var _forceSynchronousDiskWrites = false

    static var forceSynchronousDiskWrites: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _forceSynchronousDiskWrites
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _forceSynchronousDiskWrites = newValue
        }
    }
}
