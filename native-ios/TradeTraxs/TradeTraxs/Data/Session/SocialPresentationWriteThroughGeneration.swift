import Foundation

/// Prevents stale async disk writes from overwriting newer engagement (rapid like/unlike).
enum SocialPresentationWriteThroughGeneration {
    private static var tokenByKey: [String: UInt64] = [:]
    private static var nextToken: UInt64 = 0

    @MainActor
    static func bump(viewerID: ProfileID, target: InteractionTarget) -> UInt64 {
        nextToken += 1
        tokenByKey[storageKey(viewerID: viewerID, target: target)] = nextToken
        return nextToken
    }

    static func isStale(viewerID: ProfileID, target: InteractionTarget, generation: UInt64) -> Bool {
        tokenByKey[storageKey(viewerID: viewerID, target: target)] != generation
    }

    @MainActor
    static func resetForTesting() {
        tokenByKey = [:]
        nextToken = 0
    }

    private static func storageKey(viewerID: ProfileID, target: InteractionTarget) -> String {
        "\(viewerID.rawValue)|\(target.presentationStorageKey)"
    }
}
