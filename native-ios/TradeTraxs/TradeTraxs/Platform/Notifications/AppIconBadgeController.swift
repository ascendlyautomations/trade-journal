import OSLog
import UIKit
import UserNotifications

/// Smooth app-icon badge writer — single owner, no flashing.
@MainActor
final class AppIconBadgeController {
    static let shared = AppIconBadgeController()

    private var lastApplied = -1
    private var pendingTask: Task<Void, Never>?

    private init() {}

    /// Applies badge with light coalescing so rapid Realtime + push updates don't flash.
    func setBadge(_ value: Int, animated: Bool = true) {
        let next = max(0, value)
        guard next != lastApplied else { return }
        pendingTask?.cancel()
        if animated {
            pendingTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 80_000_000)
                guard !Task.isCancelled else { return }
                self?.apply(next)
            }
        } else {
            apply(next)
        }
    }

    func clear() {
        pendingTask?.cancel()
        apply(0)
    }

    private func apply(_ value: Int) {
        lastApplied = value
        UNUserNotificationCenter.current().setBadgeCount(value) { error in
            if let error {
                AppLog.notifications.error(
                    "Badge update failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }
}
