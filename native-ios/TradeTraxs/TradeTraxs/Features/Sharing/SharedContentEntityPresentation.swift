import Foundation

/// Shared-content presentation keys and cache indexing (DM + Trade Room cards).
///
/// Message ``SharedContentReference.achievementPost`` uses ``achievement_posts.id``;
/// hydrated entities are canonically keyed by ``achievements.id``.
enum SharedContentEntityPresentation {
    static func achievementLookupKey(forPostReference postReference: PostID) -> AchievementID {
        AchievementID(postReference.rawValue)
    }

    static func resolvedAchievement(
        forPostReference postReference: PostID,
        detailCache: DetailPresentationCache,
        sharedAchievements: [AchievementID: Achievement]
    ) -> Achievement? {
        let lookupKey = achievementLookupKey(forPostReference: postReference)
        if let hit = sharedAchievements[lookupKey] { return hit }
        if let hit = detailCache.achievement(forMessageReference: postReference) { return hit }
        if let canonical = detailCache.achievementID(forMessageReference: postReference),
           let hit = sharedAchievements[canonical]
        {
            return hit
        }
        return nil
    }

    static func isAchievementResolved(
        forPostReference postReference: PostID,
        detailCache: DetailPresentationCache,
        sharedAchievements: [AchievementID: Achievement]
    ) -> Bool {
        resolvedAchievement(
            forPostReference: postReference,
            detailCache: detailCache,
            sharedAchievements: sharedAchievements
        ) != nil
    }

    static func storeAchievement(
        _ achievement: Achievement,
        messagePostReference: PostID?,
        detailCache: DetailPresentationCache,
        sharedAchievements: inout [AchievementID: Achievement]
    ) {
        detailCache.seed(achievement, achievementPostID: messagePostReference)
        sharedAchievements[achievement.id] = achievement
        if let postReference = messagePostReference {
            sharedAchievements[achievementLookupKey(forPostReference: postReference)] = achievement
        }
    }

    static func messagePostReference(from reference: SharedContentReference) -> PostID? {
        guard case .achievementPost(let postID) = reference else { return nil }
        return postID
    }
}
