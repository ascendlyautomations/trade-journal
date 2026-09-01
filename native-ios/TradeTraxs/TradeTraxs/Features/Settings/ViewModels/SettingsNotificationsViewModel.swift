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

    private(set) var phase: Phase = .idle
    private(set) var preferences: NotificationPreferences?
    private(set) var saveError: String?
    /// iOS system permission — never confuse with in-app preference toggles.
    private(set) var systemAuthorization: SystemNotificationAuthorizationStatus = .notDetermined
    private var hasLoaded = false
    private var inflightKeys: Set<NotificationPreferenceKey> = []

    init(
        repository: any NotificationPreferencesRepository,
        session: any SessionProviding,
        navigationCoordinator: NavigationCoordinator,
        pushNotifications: PushNotificationCenter? = nil
    ) {
        self.repository = repository
        self.session = session
        self.navigationCoordinator = navigationCoordinator
        self.pushNotifications = pushNotifications
    }

    var masterEnabled: Bool {
        preferences?.values[.notificationsEnabled] ?? true
    }

    var systemPushStatusLabel: String {
        systemAuthorization.settingsLabel
    }

    var showsOpenSystemSettings: Bool {
        !systemAuthorization.isEnabled
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        Task { await refresh() }
    }

    func refresh() async {
        if preferences == nil {
            phase = .loading
        }
        systemAuthorization = await SystemNotificationAuthorization.currentStatus()
        do {
            guard let userID = await session.currentUserID else {
                phase = .failed("Sign in to continue.")
                return
            }
            preferences = try await repository.preferences(for: ProfileID(userID.rawValue))
            phase = .loaded
            saveError = nil
        } catch {
            if preferences == nil {
                phase = .failed(UserFacingError.message(for: error))
            } else {
                saveError = UserFacingError.message(for: error)
            }
        }
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
        systemAuthorization = await SystemNotificationAuthorization.currentStatus()
        await pushNotifications?.refreshAuthorizationStatus()
    }

    func binding(for key: NotificationPreferenceKey) -> Bool {
        preferences?.values[key] ?? true
    }

    func set(_ key: NotificationPreferenceKey, enabled: Bool) {
        guard var current = preferences else { return }
        guard current.values[key] != enabled else { return }
        let previous = current
        current.set(key, enabled: enabled)
        preferences = current
        ExperienceHaptics.play(.selection)

        guard !inflightKeys.contains(key) else { return }
        inflightKeys.insert(key)
        Task {
            defer { inflightKeys.remove(key) }
            do {
                guard let userID = await session.currentUserID else { return }
                preferences = try await repository.update(
                    [key: enabled],
                    for: ProfileID(userID.rawValue)
                )
                saveError = nil
                ExperienceHaptics.play(.success)
            } catch {
                preferences = previous
                saveError = "Couldn't save. Changes were reverted."
                ExperienceHaptics.play(.error)
            }
        }
    }
}
