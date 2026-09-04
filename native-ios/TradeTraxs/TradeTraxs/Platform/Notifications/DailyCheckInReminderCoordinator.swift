import Foundation

/// Keeps weekday daily check-in local notifications aligned with authoritative store state.
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
        let store = TraderDailyCheckInStore.shared

        await DailyCheckInReminderScheduler.sync(
            isEnabled: preferenceEnabled && authorization.isEnabled,
            isTodayCompleted: store.isCompletedToday,
            todayDateKey: store.todayDateKey
        )
    }

    func cancelAll() async {
        syncTask?.cancel()
        syncTask = nil
        await DailyCheckInReminderScheduler.cancelAll()
    }
}
