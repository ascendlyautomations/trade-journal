import Foundation
import Synchronization

/// Memory LRU → disk persistence. Disk writes are opt-in per key (public HTTP only).
nonisolated final class TieredImageCache: ImageCaching, @unchecked Sendable {
    private let memory: InMemoryImageCache
    private let disk: DiskImageCache
    private let diskEligibleKeys = Mutex(Set<String>())

    init(memory: InMemoryImageCache = InMemoryImageCache(), disk: DiskImageCache = DiskImageCache()) {
        self.memory = memory
        self.disk = disk
    }

    func markDiskEligible(key: String) {
        _ = diskEligibleKeys.withLock { $0.insert(key) }
    }

    func imageData(forKey key: String) async -> Data? {
        if let data = await memory.imageData(forKey: key) {
            #if DEBUG
            MediaEgressTracker.recordImageMemoryCacheHit(bytes: data.count)
            #endif
            return data
        }
        if let data = await disk.imageData(forKey: key) {
            #if DEBUG
            MediaEgressTracker.recordImageDiskCacheHit(bytes: data.count)
            #endif
            await memory.setImageData(data, forKey: key)
            return data
        }
        return nil
    }

    func setImageData(_ data: Data, forKey key: String) async {
        await memory.setImageData(data, forKey: key)
        let allowDisk = diskEligibleKeys.withLock { $0.contains(key) }
        if allowDisk {
            await disk.setImageData(data, forKey: key)
        }
    }

    func removeImage(forKey key: String) async {
        _ = diskEligibleKeys.withLock { $0.remove(key) }
        await memory.removeImage(forKey: key)
        await disk.removeImage(forKey: key)
    }

    func removeAllImages() async {
        diskEligibleKeys.withLock { $0.removeAll() }
        await memory.removeAllImages()
        await disk.removeAllImages()
    }

    func removeImages(matchingPrefix prefix: String) async {
        // Best-effort — memory cache has no prefix index; disk index is keyed.
        await memory.removeAllImages()
        await disk.removeAllImages()
        _ = prefix
    }
}
