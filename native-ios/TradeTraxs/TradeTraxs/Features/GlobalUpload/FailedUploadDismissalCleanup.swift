import Foundation

/// Storage objects a permanently dismissed failed job may remove.
///
/// A failed job keeps these objects so Retry can reuse them. Dismissal is permanent,
/// so unreferenced uploads are deleted. Objects tied to a saved post, trade, achievement,
/// or clip stay in place.
enum FailedUploadDismissalCleanup {
    struct Object: Hashable, Sendable {
        var bucket: String
        var path: String
    }

    static func orphanedObjects(
        post: PostUploadCheckpoint?,
        achievement: AchievementUploadCheckpoint?,
        trade: TradeSaveUploadCheckpoint?,
        story: StoryUploadCheckpoint? = nil
    ) -> [Object] {
        var objects: [Object] = []
        if let post, post.uploadedImagePublicURL != nil {
            append(
                objects: &objects,
                bucket: StorageBucket.profilePosts.rawValue,
                path: post.imageStoragePath
            )
        }
        if let story, story.savedStoryID == nil, story.insertConfirmedAbsent, story.uploadedImagePublicURL != nil {
            append(
                objects: &objects,
                bucket: StorageBucket.stories.rawValue,
                path: story.uploadedImageStoragePath
            )
        }
        if let achievement, achievement.savedAchievementID == nil, achievement.uploadedImagePublicURL != nil {
            append(
                objects: &objects,
                bucket: StorageBucket.screenshots.rawValue,
                path: achievement.uploadedImageStoragePath
            )
        }
        if let trade {
            if trade.savedTradeID == nil, trade.uploadedScreenshotPublicURL != nil {
                append(
                    objects: &objects,
                    bucket: StorageBucket.screenshots.rawValue,
                    path: trade.uploadedScreenshotStoragePath
                )
            }
            // Clip insert runs only after the trade row exists. Before that, reel
            // files are unreferenced. After the trade exists a clip row may already
            // point at them, so they stay.
            if trade.savedTradeID == nil, !trade.clipAttached {
                if trade.reelVideoPublicURL != nil {
                    append(
                        objects: &objects,
                        bucket: StorageBucket.reels.rawValue,
                        path: trade.reelVideoStoragePath
                    )
                }
                if trade.reelThumbnailPublicURL != nil {
                    append(
                        objects: &objects,
                        bucket: StorageBucket.reels.rawValue,
                        path: trade.reelThumbnailStoragePath
                    )
                }
            }
        }
        return objects
    }

    private static func append(objects: inout [Object], bucket: String, path: String?) {
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, !trimmed.contains(".."), !trimmed.contains("://") else { return }
        let object = Object(bucket: bucket, path: trimmed)
        guard !objects.contains(object) else { return }
        objects.append(object)
    }
}
