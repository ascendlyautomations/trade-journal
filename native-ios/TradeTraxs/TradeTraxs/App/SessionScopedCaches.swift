import Foundation

/// Invalidates caches that belong to the authenticated user — not the process.
///
/// Called from ``AuthenticationCoordinator`` on logout and authenticated-user changes.
/// Features must not reset these stores themselves.
@MainActor
enum SessionScopedCaches {
    static func invalidate(
        currentUserProfile: CurrentUserProfileStore,
        data: DataEnvironment
    ) {
        currentUserProfile.clear()
        MessagesInboxStore.shared.invalidate()
        data.detailCache.removeAll()
        data.engagementStore.removeAll()
    }
}
