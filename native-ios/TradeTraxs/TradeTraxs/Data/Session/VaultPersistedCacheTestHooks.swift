import Foundation

enum VaultPersistedCacheTestHooks {
    nonisolated(unsafe) static var forceSynchronousDiskWrites = false
}
