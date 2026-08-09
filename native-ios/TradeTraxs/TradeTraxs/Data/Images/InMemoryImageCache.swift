import Foundation

/// Process-lifetime image byte cache. Avoids duplicate avatar downloads.
nonisolated final class InMemoryImageCache: ImageCaching, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]
    private let maxEntries: Int

    init(maxEntries: Int = 64) {
        self.maxEntries = max(8, maxEntries)
    }

    func imageData(forKey key: String) async -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    func setImageData(_ data: Data, forKey key: String) async {
        lock.lock()
        if storage.count >= maxEntries, storage[key] == nil {
            if let first = storage.keys.first {
                storage.removeValue(forKey: first)
            }
        }
        storage[key] = data
        lock.unlock()
    }

    func removeImage(forKey key: String) async {
        lock.lock(); storage.removeValue(forKey: key); lock.unlock()
    }
}
