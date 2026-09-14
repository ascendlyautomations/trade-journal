import Foundation
import OSLog

#if DEBUG
/// DEBUG-only timing instrumentation for shared message card hydration.
@MainActor
enum SharedContentHydrationProbe {
    enum Surface: String, Sendable {
        case dm
        case tradeRoom
    }

    final class Session {
        let surface: Surface
        let startedAt: CFAbsoluteTime
        private var firstRenderableMarked = false
        private var firstRenderableAt: CFAbsoluteTime?
        private var authoritativeCompletedAt: CFAbsoluteTime?

        init(surface: Surface) {
            self.surface = surface
            startedAt = CFAbsoluteTimeGetCurrent()
        }

        func logResolution(
            type: String,
            contentID: String,
            source: String,
            result: String,
            durationMs: Int? = nil,
            reason: String? = nil,
            messageID: String? = nil,
            deduped: Bool = false
        ) {
            var parts = [
                "surface=\(surface.rawValue)",
                "type=\(type)",
                "contentID=\(contentID)",
                "deduped=\(deduped)",
                "source=\(source)",
                "result=\(result)",
            ]
            if let messageID { parts.append("messageID=\(messageID)") }
            if let durationMs { parts.append("durationMs=\(durationMs)") }
            if let reason { parts.append("reason=\(reason)") }
            log(parts.joined(separator: " "))
        }

        func logMemoryCacheHit(_ hit: Bool) {
            log("memoryCache hit=\(hit)")
        }

        func logFeedCacheHit(_ hit: Bool) {
            log("feedCache hit=\(hit)")
        }

        func logSnapshotAvailable(_ available: Bool) {
            log("snapshotAvailable=\(available)")
        }

        func logMetadataRequestStarted(type: String, count: Int) {
            log("metadataRequestStarted type=\(type) count=\(count)")
        }

        func logMetadataReturned(type: String, dtMs: Int) {
            log("metadataReturned type=\(type) dtMs=\(dtMs)")
        }

        func logThumbnailCacheHit(_ hit: Bool) {
            log("thumbnailCache hit=\(hit)")
        }

        func logHydrateBatch(trades: Int, reels: Int, posts: Int, achievements: Int) {
            log("hydrateBatch trades=\(trades) reels=\(reels) posts=\(posts) achievements=\(achievements)")
        }

        func logBatchCompleted(dtMs: Int) {
            log("batchCompleted dtMs=\(dtMs)")
        }

        func markFirstRenderableIfNeeded() {
            guard !firstRenderableMarked else { return }
            firstRenderableMarked = true
            firstRenderableAt = CFAbsoluteTimeGetCurrent()
            let dtMs = Int((firstRenderableAt! - startedAt) * 1000)
            log("firstRenderable dtMs=\(dtMs)")
        }

        func markAuthoritativeComplete() {
            authoritativeCompletedAt = CFAbsoluteTimeGetCurrent()
            let dtMs = Int((authoritativeCompletedAt! - startedAt) * 1000)
            log("authoritativeComplete dtMs=\(dtMs)")
        }

        private func log(_ message: String) {
            AppLog.general.debug("[SharedContent] \(message, privacy: .public)")
        }
    }
}
#else
@MainActor
enum SharedContentHydrationProbe {
    enum Surface: String, Sendable {
        case dm
        case tradeRoom
    }

    final class Session {
        init(surface: Surface) {}

        func logResolution(
            type: String,
            contentID: String,
            source: String,
            result: String,
            durationMs: Int? = nil,
            reason: String? = nil,
            messageID: String? = nil,
            deduped: Bool = false
        ) {}
        func logMemoryCacheHit(_ hit: Bool) {}
        func logFeedCacheHit(_ hit: Bool) {}
        func logSnapshotAvailable(_ available: Bool) {}
        func logMetadataRequestStarted(type: String, count: Int) {}
        func logMetadataReturned(type: String, dtMs: Int) {}
        func logThumbnailCacheHit(_ hit: Bool) {}
        func logHydrateBatch(trades: Int, reels: Int, posts: Int, achievements: Int) {}
        func logBatchCompleted(dtMs: Int) {}
        func markFirstRenderableIfNeeded() {}
        func markAuthoritativeComplete() {}
    }
}
#endif
