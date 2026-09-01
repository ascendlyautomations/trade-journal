import Foundation
import OSLog

/// Mirrors the backend BadgeService onto the app icon.
///
/// Native must never derive badge totals from local unread stores.
/// Every refresh fetches `GET /api/push/badge` and applies that integer.
@MainActor
enum AppIconBadgeSync {
    private static var client: (any AppIconBadgeClienting)?

    static func configure(client: any AppIconBadgeClienting) {
        self.client = client
    }

    static func refresh(animated: Bool = true) {
        guard client != nil else {
            AppLog.notifications.error("AppIconBadgeSync.refresh skipped — client not configured")
            return
        }

        Task {
            await AppIconBadgeRefreshFlight.shared.run {
                await SessionNetworkGate.shared.awaitReady()
                guard !Task.isCancelled else { return }
                do {
                    let badge = try await client!.fetchBadge()
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        AppIconBadgeController.shared.setBadge(badge, animated: animated)
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    AppLog.notifications.error(
                        "App icon badge mirror failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }
    }
}
