import Foundation

/// Session memory for recently visited Profile snapshots.
@MainActor
final class ProfileSessionStore {
    static let shared = ProfileSessionStore()

    private var snapshots: [String: ProfileState] = [:]
    private var loadedAt: [String: Date] = [:]

    private init() {}

    static func cacheKey(viewerID: ProfileID, targetProfileID: ProfileID) -> String {
        "\(viewerID.rawValue)|\(targetProfileID.rawValue)"
    }

    func restore(viewerID: ProfileID, targetProfileID: ProfileID) -> ProfileState? {
        snapshots[Self.cacheKey(viewerID: viewerID, targetProfileID: targetProfileID)]
    }

    func save(viewerID: ProfileID, targetProfileID: ProfileID, state: ProfileState) {
        let key = Self.cacheKey(viewerID: viewerID, targetProfileID: targetProfileID)
        snapshots[key] = state
        loadedAt[key] = Date()
    }

    func profileIDs(viewerID: ProfileID) -> [ProfileID] {
        let prefix = viewerID.rawValue + "|"
        return snapshots.keys.compactMap { key in
            guard key.hasPrefix(prefix) else { return nil }
            return ProfileID(String(key.dropFirst(prefix.count)))
        }
    }

    func invalidate(viewerID: ProfileID? = nil) {
        if let viewerID {
            let prefix = viewerID.rawValue + "|"
            snapshots = snapshots.filter { !$0.key.hasPrefix(prefix) }
            loadedAt = loadedAt.filter { !$0.key.hasPrefix(prefix) }
        } else {
            snapshots = [:]
            loadedAt = [:]
        }
    }
}
