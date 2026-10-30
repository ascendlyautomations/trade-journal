import Synchronization
import UIKit

/// Decoded Profile browse thumbnails (list + grid) — instant when toggling layout.
///
/// Keyed by media reference + purpose only so list and grid share one UIImage per asset.
nonisolated enum ProfileBrowseMediaDisplayCache {
    private struct State {
        var storage: [String: UIImage] = [:]
        var order: [String] = []
    }

    private static let state = Mutex(State())
    private static let maxEntries = 240

    static func cacheKey(reference: MediaReference, purpose: ImagePurpose) -> String {
        "\(reference.id)|\(purpose.rawValue)|profileBrowse"
    }

    static func uiImage(reference: MediaReference, purpose: ImagePurpose) -> UIImage? {
        let key = cacheKey(reference: reference, purpose: purpose)
        return uiImage(forKey: key)
    }

    static func uiImage(forKey key: String) -> UIImage? {
        state.withLock { cache in
            guard let image = cache.storage[key] else { return nil }
            touch(key, in: &cache)
            return image
        }
    }

    static func store(_ image: UIImage, reference: MediaReference, purpose: ImagePurpose) {
        store(image, forKey: cacheKey(reference: reference, purpose: purpose))
    }

    static func store(_ image: UIImage, forKey key: String) {
        state.withLock { cache in
            if cache.storage[key] != nil {
                cache.storage[key] = image
                touch(key, in: &cache)
                return
            }
            while cache.storage.count >= maxEntries, let oldest = cache.order.first {
                cache.order.removeFirst()
                cache.storage.removeValue(forKey: oldest)
            }
            cache.storage[key] = image
            cache.order.append(key)
        }
    }

    static func remove(reference: MediaReference, purpose: ImagePurpose) {
        remove(forKey: cacheKey(reference: reference, purpose: purpose))
    }

    static func remove(forKey key: String) {
        state.withLock { cache in
            cache.storage.removeValue(forKey: key)
            cache.order.removeAll { $0 == key }
        }
    }

    private static func touch(_ key: String, in cache: inout State) {
        cache.order.removeAll { $0 == key }
        cache.order.append(key)
    }
}
