import Foundation
import Observation

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

    private(set) var phase: Phase = .idle
    private(set) var preferences: NotificationPreferences?
    private(set) var saveError: String?
    private var hasLoaded = false
    private var inflightKeys: Set<NotificationPreferenceKey> = []

    init(
        repository: any NotificationPreferencesRepository,
        session: any SessionProviding,
        navigationCoordinator: NavigationCoordinator
    ) {
        self.repository = repository
        self.session = session
        self.navigationCoordinator = navigationCoordinator
    }

    var masterEnabled: Bool {
        preferences?.values[.notificationsEnabled] ?? true
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
        do {
            guard let userID = await session.currentUserID else {
                phase = .failed("Not signed in")
                return
            }
            preferences = try await repository.preferences(for: ProfileID(userID.rawValue))
            phase = .loaded
            saveError = nil
        } catch {
            if preferences == nil {
                phase = .failed(error.localizedDescription)
            } else {
                saveError = error.localizedDescription
            }
        }
    }

    func openCategory(_ category: NotificationPreferenceCategory) {
        guard let route = category.settingsRoute else { return }
        ExperienceHaptics.play(.selection)
        navigationCoordinator.open(.profile(.settings(route)))
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
            } catch {
                preferences = previous
                saveError = "Couldn't save. Changes were reverted."
                ExperienceHaptics.play(.warning)
            }
        }
    }
}
