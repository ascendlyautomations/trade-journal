import Foundation

/// Process-lifetime image byte cache. Avoids duplicate avatar downloads.
///
/// Bounded LRU eviction keeps long sessions from retaining every feed / chat image.
nonisolated final class InMemoryImageCache: ImageCaching, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]
    private var order: [String] = []
    private let maxEntries: Int

    init(maxEntries: Int = 64) {
        self.maxEntries = max(8, maxEntries)
    }

    func imageData(forKey key: String) async -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard let data = storage[key] else { return nil }
        touch(key)
        return data
    }

    func setImageData(_ data: Data, forKey key: String) async {
        lock.lock()
        if storage[key] != nil {
            storage[key] = data
            touch(key)
            lock.unlock()
            return
        }
        while storage.count >= maxEntries, let oldest = order.first {
            order.removeFirst()
            storage.removeValue(forKey: oldest)
        }
        storage[key] = data
        order.append(key)
        lock.unlock()
    }

    func removeImage(forKey key: String) async {
        lock.lock()
        storage.removeValue(forKey: key)
        order.removeAll { $0 == key }
        lock.unlock()
    }

    private func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
