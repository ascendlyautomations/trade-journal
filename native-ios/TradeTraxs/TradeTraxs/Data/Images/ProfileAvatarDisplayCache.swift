import Synchronization
import UIKit

/// Process-lifetime decoded profile avatars for list surfaces (Activity, Follow list, Feed chrome).
///
/// Keys match ``ImageCacheKey`` / ``DefaultImagePipeline`` so avatar identity follows media reference + purpose + sizing — not row ids.
nonisolated enum ProfileAvatarDisplayCache {
    private struct State {
        var storage: [String: UIImage] = [:]
        var order: [String] = []
    }

    private static let state = Mutex(State())
    private static let maxEntries = 96

    static func listMaxPixelSize(diameter: CGFloat) -> Int {
        max(128, Int(diameter * 3))
    }

    static func cacheKey(profile: Profile, maxPixelSize: Int) -> String? {
        guard let reference = profile.avatar else { return nil }
        return ImageCacheKey.make(
            for: ImageRequest(
                reference: reference,
                purpose: .profileAvatar,
                maxPixelSize: maxPixelSize
            )
        )
    }

    static func uiImage(forKey key: String) -> UIImage? {
        state.withLock { cache in
            guard let image = cache.storage[key] else { return nil }
            touch(key, in: &cache)
            return image
        }
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
