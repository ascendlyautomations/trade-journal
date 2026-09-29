import Foundation
import Observation

/// Session-scoped Following / Global selection — one scope for every Feed content filter.
@Observable
@MainActor
final class FeedScopeSessionStore {
    static let shared = FeedScopeSessionStore()

    private(set) var revision: UInt64 = 0
    private var scopeByViewerID: [String: FeedScope] = [:]

    private init() {}

    func scope(for viewerID: ProfileID) -> FeedScope? {
        scopeByViewerID[viewerID.rawValue]
    }

    func setScope(_ scope: FeedScope, for viewerID: ProfileID) {
        let key = viewerID.rawValue
        guard scopeByViewerID[key] != scope else { return }
        scopeByViewerID[key] = scope
        revision &+= 1
    }

    /// Seeds the in-memory scope when the viewer is first known (does not override an existing choice).
    func seedIfNeeded(scope: FeedScope, for viewerID: ProfileID) {
        guard scopeByViewerID[viewerID.rawValue] == nil else { return }
        setScope(scope, for: viewerID)
    }

    /// Resolves the first scope for bootstrap: session memory → saved preference → following-count default.
    func resolvedInitialScope(
        userID: UserID,
        profileStore: CurrentUserProfileStore?
    ) async -> FeedScope {
        let viewerID = ProfileID(userID.rawValue)
        if let session = scope(for: viewerID) {
            return session
        }
        if let saved = FeedScopePreferenceStore.savedScope(for: userID) {
            setScope(saved, for: viewerID)
            return saved
        }
        let initial = await FeedInitialScopeResolver.resolvedInitialScope(
            userID: userID,
            profileStore: profileStore
        )
        setScope(initial, for: viewerID)
        return initial
    }

    func invalidate(viewerID: ProfileID? = nil) {
        if let viewerID {
            scopeByViewerID.removeValue(forKey: viewerID.rawValue)
        } else {
            scopeByViewerID = [:]
        }
        revision &+= 1
    }
}
