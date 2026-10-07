import Foundation

/// Registers for ``Notification.Name/userBlockListDidChange`` and syncs block peers when a repository is available.
@MainActor
enum DiscoveryBlockedPeersObserver {
    static func install(
        messages: (any MessageRepository)?,
        onChange: @escaping @MainActor () -> Void
    ) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: .userBlockListDidChange,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                if let messages {
                    await FeedBlockedAuthorsFilter.shared.syncFromServer(messages: messages, force: true)
                }
                onChange()
            }
        }
    }

    static func sync(messages: (any MessageRepository)?, force: Bool) async {
        guard let messages else { return }
        await FeedBlockedAuthorsFilter.shared.syncFromServer(messages: messages, force: force)
    }
}
