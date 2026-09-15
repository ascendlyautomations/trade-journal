import Foundation

/// Keeps trade-import local notifications aligned with device preference + iOS authorization.
@MainActor
final class TradeImportReminderCoordinator {
    static let shared = TradeImportReminderCoordinator()

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
        let preferenceEnabled = TradeImportReminderPreferences.isEnabled
        await TradeImportReminderScheduler.sync(
            isEnabled: preferenceEnabled && authorization.isEnabled
        )
    }

    func cancelAll() async {
        syncTask?.cancel()
        syncTask = nil
        await TradeImportReminderScheduler.cancelAll()
    }
}
