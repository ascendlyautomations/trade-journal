import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class SettingsNotificationsViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private let repository: any NotificationPreferencesRepository
    private let session: any SessionProviding
    private let navigationCoordinator: NavigationCoordinator
    private let pushNotifications: PushNotificationCenter?
    private let preferencesStore: NotificationPreferencesSessionStore

    init(
        repository: any NotificationPreferencesRepository,
        session: any SessionProviding,
        navigationCoordinator: NavigationCoordinator,
        pushNotifications: PushNotificationCenter? = nil,
        preferencesStore: NotificationPreferencesSessionStore? = nil
    ) {
        self.repository = repository
        self.session = session
        self.navigationCoordinator = navigationCoordinator
        self.pushNotifications = pushNotifications
        self.preferencesStore = preferencesStore ?? NotificationPreferencesSessionStore.shared
    }

    var phase: Phase {
        preferencesStore.phase
    }

    var preferences: NotificationPreferences? {
        preferencesStore.preferences
    }

    var saveError: String? {
        preferencesStore.saveError
    }

    /// iOS system permission — never confuse with in-app preference toggles.
    private(set) var systemAuthorization: SystemNotificationAuthorizationStatus = .notDetermined
    private(set) var hasResolvedSystemAuthorization = false

    /// Mirrors device-local reminder prefs — drives toggle UI (`@Observable` does not observe UserDefaults).
    private(set) var dailyCheckInReminderOn = DailyCheckInReminderPreferences.isEnabled
    private(set) var tradeImportReminderOn = TradeImportReminderPreferences.isEnabled

    var masterEnabled: Bool {
        preferencesStore.masterEnabled
    }

    var systemPushStatusLabel: String {
        systemAuthorization.settingsLabel
    }

    /// True once `UNUserNotificationCenter` status is known — avoids grayed-out ON toggles before refresh.
    var showsOpenSystemSettings: Bool {
        hasResolvedSystemAuthorization && systemAuthorization == .denied
    }

    var showsRequestSystemNotificationAuthorization: Bool {
        hasResolvedSystemAuthorization && systemAuthorization == .notDetermined
    }

    func setDailyCheckInReminderEnabled(_ enabled: Bool) {
        if applyLocalReminderToggleImmediatelyIfPossible(
            enabled: enabled,
            persist: { DailyCheckInReminderPreferences.isEnabled = $0 },
            assign: { dailyCheckInReminderOn = $0 },
            current: { dailyCheckInReminderOn },
            sync: { await DailyCheckInReminderCoordinator.shared.sync() }
        ) {
            return
        }
        Task {
            await applyLocalReminderToggle(
                enabled: enabled,
                persist: { DailyCheckInReminderPreferences.isEnabled = $0 },
                assign: { dailyCheckInReminderOn = $0 },
                current: { dailyCheckInReminderOn },
                sync: { await DailyCheckInReminderCoordinator.shared.sync() }
            )
        }
    }

    func setTradeImportReminderEnabled(_ enabled: Bool) {
        if applyLocalReminderToggleImmediatelyIfPossible(
            enabled: enabled,
            persist: { TradeImportReminderPreferences.isEnabled = $0 },
            assign: { tradeImportReminderOn = $0 },
            current: { tradeImportReminderOn },
            sync: { await TradeImportReminderCoordinator.shared.sync() }
        ) {
            return
        }
        Task {
            await applyLocalReminderToggle(
                enabled: enabled,
                persist: { TradeImportReminderPreferences.isEnabled = $0 },
                assign: { tradeImportReminderOn = $0 },
                current: { tradeImportReminderOn },
                sync: { await TradeImportReminderCoordinator.shared.sync() }
            )
        }
    }

    func loadIfNeeded() {
        preferencesStore.loadIfNeeded(repository: repository, session: session)
    }

    func refresh() async {
        await refreshSystemAuthorization()
        await preferencesStore.refresh(repository: repository, session: session, force: true)
    }

    func openSystemSettings() {
        if let pushNotifications {
            pushNotifications.openSystemSettings()
            return
        }
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func refreshSystemAuthorization() async {
        await refreshSystemAuthorizationStatusOnly()
        reloadLocalReminderToggleStateFromPersistence()
        TradeImportReminderPreferences.applyDefaultIfNeeded(
            authorizationGranted: systemAuthorization.isEnabled
        )
        reloadLocalReminderToggleStateFromPersistence()
        await syncLocalReminderCoordinatorsIfAuthorized()
    }

    func requestSystemNotificationAuthorization() async {
        _ = await SystemNotificationAuthorization.requestAuthorization()
        await refreshSystemAuthorizationStatusOnly()
        TradeImportReminderPreferences.applyDefaultIfNeeded(
            authorizationGranted: systemAuthorization.isEnabled
        )
        reloadLocalReminderToggleStateFromPersistence()
        await syncLocalReminderCoordinatorsIfAuthorized()
    }

    var isLocalReminderToggleInteractive: Bool {
        hasResolvedSystemAuthorization && systemAuthorization != .denied
    }

    private func refreshSystemAuthorizationStatusOnly() async {
        systemAuthorization = await SystemNotificationAuthorization.currentStatus()
        hasResolvedSystemAuthorization = true
        await pushNotifications?.refreshAuthorizationStatus()
    }

    private func reloadLocalReminderToggleStateFromPersistence() {
        dailyCheckInReminderOn = DailyCheckInReminderPreferences.isEnabled
        tradeImportReminderOn = TradeImportReminderPreferences.isEnabled
    }

    private func syncLocalReminderCoordinatorsIfAuthorized() async {
        guard systemAuthorization.isEnabled else { return }
        await DailyCheckInReminderCoordinator.shared.sync()
        await TradeImportReminderCoordinator.shared.sync()
    }

    @discardableResult
    private func applyLocalReminderToggleImmediatelyIfPossible(
        enabled: Bool,
        persist: (Bool) -> Void,
        assign: (Bool) -> Void,
        current: () -> Bool,
        sync: @escaping () async -> Void
    ) -> Bool {
        guard hasResolvedSystemAuthorization else { return false }
        guard systemAuthorization != .denied else { return false }
        if enabled, !systemAuthorization.isEnabled { return false }
        guard current() != enabled else { return true }
        assign(enabled)
        persist(enabled)
        ExperienceHaptics.play(.selection)
        Task { await sync() }
        return true
    }

    private func applyLocalReminderToggle(
        enabled: Bool,
        persist: (Bool) -> Void,
        assign: (Bool) -> Void,
        current: () -> Bool,
        sync: @escaping () async -> Void
    ) async {
        if !hasResolvedSystemAuthorization {
            await refreshSystemAuthorizationStatusOnly()
        }

        if systemAuthorization == .denied {
            return
        }

        if enabled, !systemAuthorization.isEnabled {
            if systemAuthorization == .notDetermined {
                await requestSystemNotificationAuthorization()
            }
            guard systemAuthorization.isEnabled else { return }
        }

        guard current() != enabled else { return }

        assign(enabled)
        persist(enabled)
        ExperienceHaptics.play(.selection)
        await sync()
    }

    func binding(for key: NotificationPreferenceKey) -> Bool {
        preferencesStore.binding(for: key)
    }

    func set(_ key: NotificationPreferenceKey, enabled: Bool) {
        preferencesStore.set(
            key,
            enabled: enabled,
            repository: repository,
            session: session
        )
    }
}