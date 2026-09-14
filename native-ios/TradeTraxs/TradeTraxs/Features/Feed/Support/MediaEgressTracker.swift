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

    // MARK: - Public API

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
        case .image: imagesBytes += byteCount
        case .video: videosBytes += byteCount
        case .avatar: avatarsBytes += byteCount
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
            clipsMB=\(megabytes(clipsBytes))
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
