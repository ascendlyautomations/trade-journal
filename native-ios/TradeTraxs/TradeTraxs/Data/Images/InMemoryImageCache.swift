import Foundation
import Synchronization

/// Process-lifetime image byte cache. Avoids duplicate avatar downloads.
///
/// Bounded LRU eviction keeps long sessions from retaining every feed / chat image.
nonisolated final class InMemoryImageCache: ImageCaching, @unchecked Sendable {
    private struct CacheState {
        var storage: [String: Data] = [:]
        var order: [String] = []
    }

    private let state = Mutex(CacheState())
    private let maxEntries: Int

    init(maxEntries: Int = 64) {
        self.maxEntries = max(8, maxEntries)
    }

    func imageData(forKey key: String) async -> Data? {
        state.withLock { cache in
            guard let data = cache.storage[key] else { return nil }
            touch(key, in: &cache)
            return data
        }
    }

    func setImageData(_ data: Data, forKey key: String) async {
        state.withLock { cache in
            if cache.storage[key] != nil {
                cache.storage[key] = data
                touch(key, in: &cache)
                return
            }
            while cache.storage.count >= maxEntries, let oldest = cache.order.first {
                cache.order.removeFirst()
                cache.storage.removeValue(forKey: oldest)
            }
            cache.storage[key] = data
            cache.order.append(key)
        }
    }

    func removeImage(forKey key: String) async {
        state.withLock { cache in
            cache.storage.removeValue(forKey: key)
            cache.order.removeAll { $0 == key }
        }
    }

    private func touch(_ key: String, in cache: inout CacheState) {
        cache.order.removeAll { $0 == key }
        cache.order.append(key)
    }
}
