import Foundation

enum SocialPresentationWriteThroughSource: String, Sendable {
    case feed
    case profile
    case detail
    case comments
    case engagementStore
    case engagementRealtime
}

/// Bounded presentation write-through — patches already-cached Feed/Profile snapshots only.
@MainActor
protocol SocialPresentationWriteThroughClient: AnyObject {
    func propagateEngagement(
        target: InteractionTarget,
        snapshot: EngagementSnapshot,
        source: SocialPresentationWriteThroughSource,
        isRollback: Bool
    ) async
}

@MainActor
final class SocialPresentationWriteThroughCoordinator: SocialPresentationWriteThroughClient {
    static let shared = SocialPresentationWriteThroughCoordinator()

    private var session: (any SessionProviding)?

    func configure(session: any SessionProviding) {
        self.session = session
    }

    func propagateEngagement(
        target: InteractionTarget,
        snapshot: EngagementSnapshot,
        source: SocialPresentationWriteThroughSource,
        isRollback: Bool
    ) async {
        guard let session else { return }
        guard let viewerID = await session.currentUserID.map({ ProfileID($0.rawValue) }) else { return }

        let started = CFAbsoluteTimeGetCurrent()
        let generation = SocialPresentationWriteThroughGeneration.bump(viewerID: viewerID, target: target)

        let feedCopies = FeedPersistedCacheCoordinator.patchEngagement(
            viewerID: viewerID,
            target: target,
            snapshot: snapshot,
            writeGeneration: generation
        )
        let profileCopies = ProfilePersistedCacheCoordinator.patchEngagementPresentation(
            viewerID: viewerID,
            target: target,
            snapshot: snapshot,
            writeGeneration: generation
        )

        #if DEBUG
        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
        if isRollback {
            print(
                """
                [SocialWriteThrough][Rollback] viewer=\(viewerID.rawValue) \
                targetType=\(target.kind.rawValue) targetID=\(target.id) \
                feedCopies=\(feedCopies) profileCopies=\(profileCopies) entityDisk=0 source=\(source.rawValue)
                """
            )
        } else {
            print(
                """
                [SocialWriteThrough][Patch] viewer=\(viewerID.rawValue) \
                targetType=\(target.kind.rawValue) targetID=\(target.id) \
                feedCopies=\(feedCopies) profileCopies=\(profileCopies) entityDisk=0 source=\(source.rawValue) \
                elapsedMs=\(max(0, elapsedMs))
                """
            )
        }
        SocialPresentationWriteThroughProbe.recordPropagation(
            feedCopies: feedCopies,
            profileCopies: profileCopies
        )
        #else
        _ = isRollback
        _ = source
        #endif
    }
}

#if DEBUG
enum SocialPresentationWriteThroughProbe {
    static var lastFeedCopies = 0
    static var lastProfileCopies = 0
    static var propagationCount = 0

    static func recordPropagation(feedCopies: Int, profileCopies: Int) {
        lastFeedCopies = feedCopies
        lastProfileCopies = profileCopies
        propagationCount += 1
    }

    static func resetForTesting() {
        lastFeedCopies = 0
        lastProfileCopies = 0
        propagationCount = 0
    }
}
#endif
