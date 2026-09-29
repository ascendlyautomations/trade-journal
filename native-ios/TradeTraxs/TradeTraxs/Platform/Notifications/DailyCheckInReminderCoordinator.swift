import Foundation

/// Keeps weekday daily check-in local notifications aligned with device preference + authorization.
@MainActor
final class DailyCheckInReminderCoordinator {
    static let shared = DailyCheckInReminderCoordinator()

    private var syncTask: Task<Void, Never>?

    private init() {}

    func syncIfNeeded() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            await self?.sync()
        }
    }

    func sync() async {
        guard !Task.isCancelled else { return }

        let authorization = await SystemNotificationAuthorization.currentStatus()
        let preferenceEnabled = DailyCheckInReminderPreferences.isEnabled

        await DailyCheckInReminderScheduler.sync(
            isEnabled: preferenceEnabled && authorization.isEnabled
        )
    }

    func cancelAll() async {
        syncTask?.cancel()
        syncTask = nil
        await DailyCheckInReminderScheduler.cancelAll()
    }
}
