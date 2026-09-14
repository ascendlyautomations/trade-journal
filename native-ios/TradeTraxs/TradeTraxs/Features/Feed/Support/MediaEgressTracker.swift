import AVFoundation
import Foundation

#if DEBUG
/// DEBUG-only network media egress accounting — counts actual transferred bytes once per HTTP response / access-log delta.
enum MediaEgressTracker {
    enum MediaType: String {
        case image
        case video
        case avatar
        case other
    }

    nonisolated private static let lock = NSLock()
    nonisolated(unsafe) private static var networkRequests = 0
    nonisolated(unsafe) private static var totalBytes: Int64 = 0
    nonisolated(unsafe) private static var imagesBytes: Int64 = 0
    nonisolated(unsafe) private static var videosBytes: Int64 = 0
    nonisolated(unsafe) private static var avatarsBytes: Int64 = 0
    nonisolated(unsafe) private static var otherTypeBytes: Int64 = 0
    nonisolated(unsafe) private static var feedBytes: Int64 = 0
    nonisolated(unsafe) private static var detailBytes: Int64 = 0
    nonisolated(unsafe) private static var clipsBytes: Int64 = 0
    nonisolated(unsafe) private static var profileBytes: Int64 = 0
    nonisolated(unsafe) private static var otherSurfaceBytes: Int64 = 0
    nonisolated(unsafe) private static var periodicTimer: Timer?
    nonisolated(unsafe) private static var imageMemoryCacheHits = 0
    nonisolated(unsafe) private static var imageDiskCacheHits = 0
    nonisolated(unsafe) private static var imageCacheMisses = 0
    nonisolated(unsafe) private static var imageCoalescedDuplicates = 0
    nonisolated(unsafe) private static var imagePrefetchCancelled = 0
    nonisolated(unsafe) private static var imageMemoryCacheHitBytes: Int64 = 0
    nonisolated(unsafe) private static var imageDiskCacheHitBytes: Int64 = 0
    nonisolated(unsafe) private static var imageNetworkRequests = 0
    nonisolated(unsafe) private static var videoNetworkRequests = 0

    struct SessionSnapshot: Sendable {
        var imageNetworkRequests: Int
        var imageNetworkBytes: Int64
        var videoNetworkBytes: Int64
        var videoNetworkRequests: Int
        var imageMemoryCacheHits: Int
        var imageDiskCacheHits: Int
        var imageCacheMisses: Int
        var imageCoalescedDuplicates: Int
        var imagePrefetchCancelled: Int
    }

    // MARK: - Public API

    nonisolated static func resetSessionCounters() {
        lock.lock()
        networkRequests = 0
        totalBytes = 0
        imagesBytes = 0
        videosBytes = 0
        avatarsBytes = 0
        otherTypeBytes = 0
        feedBytes = 0
        detailBytes = 0
        clipsBytes = 0
        profileBytes = 0
        otherSurfaceBytes = 0
        imageMemoryCacheHits = 0
        imageDiskCacheHits = 0
        imageCacheMisses = 0
        imageCoalescedDuplicates = 0
        imagePrefetchCancelled = 0
        imageMemoryCacheHitBytes = 0
        imageDiskCacheHitBytes = 0
        imageNetworkRequests = 0
        videoNetworkRequests = 0
        lock.unlock()
    }

    nonisolated static func sessionSnapshot() -> SessionSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return SessionSnapshot(
            imageNetworkRequests: imageNetworkRequests,
            imageNetworkBytes: imagesBytes + avatarsBytes,
            videoNetworkBytes: videosBytes,
            videoNetworkRequests: videoNetworkRequests,
            imageMemoryCacheHits: imageMemoryCacheHits,
            imageDiskCacheHits: imageDiskCacheHits,
            imageCacheMisses: imageCacheMisses,
            imageCoalescedDuplicates: imageCoalescedDuplicates,
            imagePrefetchCancelled: imagePrefetchCancelled
        )
    }

    nonisolated static func recordImageMemoryCacheHit(bytes: Int) {
        lock.lock()
        imageMemoryCacheHits += 1
        imageMemoryCacheHitBytes += Int64(bytes)
        lock.unlock()
    }

    nonisolated static func recordImageDiskCacheHit(bytes: Int) {
        lock.lock()
        imageDiskCacheHits += 1
        imageDiskCacheHitBytes += Int64(bytes)
        lock.unlock()
    }

    nonisolated static func recordImageCacheMiss() {
        lock.lock()
        imageCacheMisses += 1
        lock.unlock()
    }

    nonisolated static func recordImageCoalescedDuplicate() {
        lock.lock()
        imageCoalescedDuplicates += 1
        lock.unlock()
    }

    nonisolated static func recordImagePrefetchCancelled() {
        lock.lock()
        imagePrefetchCancelled += 1
        lock.unlock()
    }

    nonisolated static func recordNetworkTransfer(
        type: MediaType,
        surface: String,
        mediaID: String,
        bytes: Int
    ) {
        guard bytes > 0 else { return }

        lock.lock()
        defer { lock.unlock() }

        networkRequests += 1
        let byteCount = Int64(bytes)
        totalBytes += byteCount

        switch type {
        case .image:
            imagesBytes += byteCount
            imageNetworkRequests += 1
        case .video:
            videosBytes += byteCount
            videoNetworkRequests += 1
        case .avatar:
            avatarsBytes += byteCount
            imageNetworkRequests += 1
        case .other: otherTypeBytes += byteCount
        }

        switch normalizedSurface(surface) {
        case "feed": feedBytes += byteCount
        case "detail": detailBytes += byteCount
        case "clips": clipsBytes += byteCount
        case "profile": profileBytes += byteCount
        default: otherSurfaceBytes += byteCount
        }

        let sessionTotalMB = megabytes(totalBytes)
        let sessionTotalGB = gigabytes(totalBytes)

        print(
            """
            [MEDIA_EGRESS] \
            type=\(type.rawValue) \
            surface=\(normalizedSurface(surface)) \
            mediaID=\(truncatedMediaID(mediaID)) \
            bytes=\(bytes) \
            KB=\(kilobytes(bytes)) \
            MB=\(megabytes(byteCount)) \
            sessionTotalMB=\(sessionTotalMB) \
            sessionTotalGB=\(sessionTotalGB) \
            networkRequests=\(networkRequests) \
            imagesMB=\(megabytes(imagesBytes)) \
            videosMB=\(megabytes(videosBytes)) \
            avatarsMB=\(megabytes(avatarsBytes)) \
            otherMB=\(megabytes(otherTypeBytes)) \
            feedMB=\(megabytes(feedBytes)) \
            detailMB=\(megabytes(detailBytes)) \
            clipsMB=\(megabytes(clipsBytes)) \
            profileMB=\(megabytes(profileBytes))
            """
        )
    }

    nonisolated static func printSummary() {
        lock.lock()
        defer { lock.unlock() }

        print(
            """
            [MEDIA_EGRESS_SUMMARY] \
            networkRequests=\(networkRequests) \
            totalBytes=\(totalBytes) \
            totalMB=\(megabytes(totalBytes)) \
            totalGB=\(gigabytes(totalBytes)) \
            imagesMB=\(megabytes(imagesBytes)) \
            videosMB=\(megabytes(videosBytes)) \
            avatarsMB=\(megabytes(avatarsBytes)) \
            feedMB=\(megabytes(feedBytes)) \
            detailMB=\(megabytes(detailBytes)) \
            clipsMB=\(megabytes(clipsBytes)) \
            imageNetworkRequests=\(networkRequests) \
            imageMemoryCacheHits=\(imageMemoryCacheHits) \
            imageDiskCacheHits=\(imageDiskCacheHits) \
            imageCacheMisses=\(imageCacheMisses) \
            imageCoalescedDuplicates=\(imageCoalescedDuplicates) \
            imagePrefetchCancelled=\(imagePrefetchCancelled) \
            imageMemoryHitMB=\(megabytes(imageMemoryCacheHitBytes)) \
            imageDiskHitMB=\(megabytes(imageDiskCacheHitBytes))
            """
        )
    }

    nonisolated static func startPeriodicSummaries(interval: TimeInterval = 60) {
        DispatchQueue.main.async {
            periodicTimer?.invalidate()
            periodicTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
                printSummary()
            }
        }
    }

    nonisolated static func stopPeriodicSummaries() {
        DispatchQueue.main.async {
            periodicTimer?.invalidate()
            periodicTimer = nil
        }
    }

    // MARK: - Image pipeline helpers

    nonisolated static func mediaType(for purpose: ImagePurpose) -> MediaType {
        switch purpose {
        case .profileAvatar: return .avatar
        case .postImage, .tradeScreenshot, .storyMedia, .reelThumbnail: return .image
        }
    }

    nonisolated static func surface(for request: ImageRequest) -> String {
        if !request.auditSurface.isEmpty {
            return normalizedSurface(request.auditSurface)
        }
        switch request.purpose {
        case .profileAvatar: return "profile"
        case .postImage, .tradeScreenshot: return "feed"
        case .storyMedia: return "stories"
        case .reelThumbnail: return "clips"
        }
    }

    // MARK: - Video access-log helper

    nonisolated(unsafe) private static var videoAccessObservers: [ObjectIdentifier: VideoAccessState] = [:]

    private final class VideoAccessState {
        let observer: NSObjectProtocol
        let mediaID: String
        let surface: String
        weak var item: AVPlayerItem?

        init(
            observer: NSObjectProtocol,
            mediaID: String,
            surface: String,
            item: AVPlayerItem
        ) {
            self.observer = observer
            self.mediaID = mediaID
            self.surface = surface
            self.item = item
        }
    }

    @MainActor
    static func installVideoAccessLog(
        on item: AVPlayerItem,
        mediaID: String,
        surface: String
    ) {
        let key = ObjectIdentifier(item)
        removeVideoAccessLog(for: item)

        let normalized = normalizedSurface(surface)
        VideoAccessLogAccounting.registerItem(player: nil, item: item)
        let state = VideoAccessState(
            observer: NotificationCenter.default.addObserver(
                forName: .AVPlayerItemNewAccessLogEntry,
                object: item,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    handleVideoAccessLog(itemKey: key)
                }
            },
            mediaID: mediaID,
            surface: normalized,
            item: item
        )
        videoAccessObservers[key] = state
    }

    @MainActor
    static func removeVideoAccessLog(for item: AVPlayerItem) {
        let key = ObjectIdentifier(item)
        VideoAccessLogAccounting.unregisterItem(item)
        if let existing = videoAccessObservers.removeValue(forKey: key) {
            NotificationCenter.default.removeObserver(existing.observer)
        }
    }

    @MainActor
    private static func handleVideoAccessLog(itemKey: ObjectIdentifier) {
        guard let state = videoAccessObservers[itemKey] else { return }
        guard let item = state.item else {
            videoAccessObservers.removeValue(forKey: itemKey)
            return
        }
        guard let accounting = VideoAccessLogAccounting.processNewAccessLogEntry(item: item, player: nil) else {
            return
        }
        guard accounting.newBytes > 0 else { return }
        recordNetworkTransfer(
            type: .video,
            surface: state.surface,
            mediaID: state.mediaID,
            bytes: Int(accounting.newBytes)
        )
    }

    // MARK: - Formatting

    nonisolated private static func kilobytes(_ bytes: Int) -> String {
        String(format: "%.2f", Double(bytes) / 1024.0)
    }

    nonisolated private static func megabytes(_ bytes: Int64) -> String {
        String(format: "%.3f", Double(bytes) / 1_048_576.0)
    }

    nonisolated private static func gigabytes(_ bytes: Int64) -> String {
        String(format: "%.6f", Double(bytes) / 1_073_741_824.0)
    }

    nonisolated private static func normalizedSurface(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return "other" }
        switch trimmed {
        case "feed", "feed-inline", "feedinline": return "feed"
        case "detail", "post-detail", "trade-detail": return "detail"
        case "clips", "clips-pager", "clipspager", "clips-prefetch": return "clips"
        case "profile": return "profile"
        case "stories", "story": return "stories"
        default: return trimmed
        }
    }

    nonisolated private static func truncatedMediaID(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 96 { return trimmed }
        return String(trimmed.prefix(96)) + "…"
    }
}

#else
enum MediaEgressTracker {
    enum MediaType: String { case image, video, avatar, other }

    struct SessionSnapshot: Sendable {
        var imageNetworkRequests: Int = 0
        var imageNetworkBytes: Int64 = 0
        var videoNetworkBytes: Int64 = 0
        var videoNetworkRequests: Int = 0
        var imageMemoryCacheHits: Int = 0
        var imageDiskCacheHits: Int = 0
        var imageCacheMisses: Int = 0
        var imageCoalescedDuplicates: Int = 0
        var imagePrefetchCancelled: Int = 0
    }

    static func resetSessionCounters() {}
    static func sessionSnapshot() -> SessionSnapshot { SessionSnapshot() }
    static func recordImageMemoryCacheHit(bytes: Int) {}
    static func recordImageDiskCacheHit(bytes: Int) {}
    static func recordImageCacheMiss() {}
    static func recordImageCoalescedDuplicate() {}
    static func recordImagePrefetchCancelled() {}
    static func recordNetworkTransfer(type: MediaType, surface: String, mediaID: String, bytes: Int) {}
    static func printSummary() {}
    static func startPeriodicSummaries(interval: TimeInterval = 60) {}
    static func stopPeriodicSummaries() {}
    static func mediaType(for purpose: ImagePurpose) -> MediaType { .other }
    static func surface(for request: ImageRequest) -> String { "other" }
    static func installVideoAccessLog(on item: AVPlayerItem, mediaID: String, surface: String) {}
    static func removeVideoAccessLog(for item: AVPlayerItem) {}
}
#endif
