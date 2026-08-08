import Foundation

/// In-process memory cache.
nonisolated protocol MemoryCaching: Sendable {
    func value<T: Sendable>(forKey key: String, as type: T.Type) -> T?
    func set<T: Sendable>(_ value: T, forKey key: String)
    func remove(forKey key: String)
    func removeAll()
}

/// Durable disk cache — SwiftData / file store later.
nonisolated protocol DiskCaching: Sendable {
    func data(forKey key: String) async throws -> Data?
    func set(_ data: Data, forKey key: String) async throws
    func remove(forKey key: String) async throws
    func removeAll() async throws
}

/// Image-specific cache (decoded / encoded bytes).
nonisolated protocol ImageCaching: Sendable {
    func imageData(forKey key: String) async -> Data?
    func setImageData(_ data: Data, forKey key: String) async
    func removeImage(forKey key: String) async
}

/// Query / response cache keyed by logical request identity.
nonisolated protocol QueryCaching: Sendable {
    func cachedData(forQueryKey key: String) async -> Data?
    func store(_ data: Data, forQueryKey key: String, ttl: TimeInterval) async
    func invalidate(queryKey key: String) async
    func invalidateAll() async
}

nonisolated final class PlaceholderMemoryCache: MemoryCaching, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Any] = [:]

    func value<T: Sendable>(forKey key: String, as type: T.Type) -> T? {
        lock.lock(); defer { lock.unlock() }
        return storage[key] as? T
    }

    func set<T: Sendable>(_ value: T, forKey key: String) {
        lock.lock(); storage[key] = value; lock.unlock()
    }

    func remove(forKey key: String) {
        lock.lock(); storage.removeValue(forKey: key); lock.unlock()
    }

    func removeAll() {
        lock.lock(); storage.removeAll(); lock.unlock()
    }
}

nonisolated struct PlaceholderDiskCache: DiskCaching {
    func data(forKey key: String) async throws -> Data? {
        _ = key
        return nil
    }

    func set(_ data: Data, forKey key: String) async throws {
        _ = (data, key)
    }

    func remove(forKey key: String) async throws {
        _ = key
    }

    func removeAll() async throws {}
}

nonisolated struct PlaceholderImageCache: ImageCaching {
    func imageData(forKey key: String) async -> Data? {
        _ = key
        return nil
    }

    func setImageData(_ data: Data, forKey key: String) async {
        _ = (data, key)
    }

    func removeImage(forKey key: String) async {
        _ = key
    }
}

nonisolated struct PlaceholderQueryCache: QueryCaching {
    func cachedData(forQueryKey key: String) async -> Data? {
        _ = key
        return nil
    }

    func store(_ data: Data, forQueryKey key: String, ttl: TimeInterval) async {
        _ = (data, key, ttl)
    }

    func invalidate(queryKey key: String) async {
        _ = key
    }

    func invalidateAll() async {}
}

nonisolated struct CacheStack: Sendable {
    var memory: any MemoryCaching
    var disk: any DiskCaching
    var images: any ImageCaching
    var queries: any QueryCaching

    static func placeholder() -> CacheStack {
        CacheStack(
            memory: PlaceholderMemoryCache(),
            disk: PlaceholderDiskCache(),
            images: PlaceholderImageCache(),
            queries: PlaceholderQueryCache()
        )
    }
}
