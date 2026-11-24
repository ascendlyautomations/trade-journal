import Foundation
import Observation

/// Session-scoped notification preference state, shared across Settings notification routes.
@MainActor
@Observable
final class NotificationPreferencesSessionStore {
    static let shared = NotificationPreferencesSessionStore()

    private(set) var preferences: NotificationPreferences?
    private(set) var phase: SettingsNotificationsViewModel.Phase = .idle
    private(set) var saveError: String?

    private var hasLoadedAuthoritative = false
    private var outbox: [NotificationPreferenceKey: Bool] = [:]
    private var isDraining = false
    private var saveEpoch: UInt64 = 0

    private init() {}

    func binding(for key: NotificationPreferenceKey) -> Bool {
        preferences?.values[key] ?? true
    }

    var masterEnabled: Bool {
        preferences?.values[.notificationsEnabled] ?? true
    }

    func loadIfNeeded(
        repository: any NotificationPreferencesRepository,
        session: any SessionProviding,
        force: Bool = false
    ) {
        if force {
            Task { await refresh(repository: repository, session: session, force: true) }
            return
        }
        if hasLoadedAuthoritative, preferences != nil {
            phase = .loaded
            return
        }
        guard phase != .loading else { return }
        Task { await refresh(repository: repository, session: session, force: false) }
    }

    func refresh(
        repository: any NotificationPreferencesRepository,
        session: any SessionProviding,
        force: Bool
    ) async {
        if preferences == nil {
            phase = .loading
        }
        do {
            guard let userID = await session.currentUserID else {
                phase = .failed("Sign in to continue.")
                return
            }
            let profileID = ProfileID(userID.rawValue)
            if force {
                repository.invalidateCachedPreferences(for: profileID)
            }
            let loaded = try await repository.preferences(for: profileID, forceRefresh: force)
            applyAuthoritativeLoad(loaded)
        } catch {
            NotificationPreferencesSaveDiagnostics.logLoadFailure(error)
            let message = UserFacingError.message(for: error)
            if preferences == nil {
                phase = .failed(message)
            } else {
                saveError = message
            }
        }
    }

    func set(
        _ key: NotificationPreferenceKey,
        enabled: Bool,
        repository: any NotificationPreferencesRepository,
        session: any SessionProviding
    ) {
        guard var current = preferences else { return }
        guard current.values[key] != enabled else { return }

        current.set(key, enabled: enabled)
        preferences = current
        saveEpoch &+= 1
        outbox[key] = enabled
        saveError = nil
        ExperienceHaptics.play(.selection)

        if AppLaunchController.shared.isDemoExperienceActive {
            return
        }

        Task {
            await drainOutbox(repository: repository, session: session)
        }
    }

    func resetForSessionBoundary() {
        preferences = nil
        phase = .idle
        saveError = nil
        hasLoadedAuthoritative = false
        outbox = [:]
        isDraining = false
        saveEpoch = 0
    }

    private func applyAuthoritativeLoad(_ loaded: NotificationPreferences) {
        preferences = loaded
        phase = .loaded
        saveError = nil
        hasLoadedAuthoritative = true
    }

    private func drainOutbox(
        repository: any NotificationPreferencesRepository,
        session: any SessionProviding
    ) async {
        guard !isDraining else { return }
        isDraining = true
        defer { isDraining = false }

        while !outbox.isEmpty {
            guard let userID = await session.currentUserID else { return }

            let batch = outbox
            outbox = [:]
            let epochAtStart = saveEpoch
            let snapshot = preferences

            do {
                let server = try await repository.update(
                    batch,
                    for: ProfileID(userID.rawValue)
                )
                mergeServerResponse(server, appliedBatch: batch)
                if !outbox.isEmpty || saveEpoch != epochAtStart {
                    continue
                }
                saveError = nil
                ExperienceHaptics.play(.success)
            } catch {
                NotificationPreferencesSaveDiagnostics.logSaveFailure(error, patch: batch)
                if saveEpoch == epochAtStart {
                    revertFailedBatch(
                        batch,
                        snapshot: snapshot,
                        epochAtStart: epochAtStart
                    )
                    saveError = NotificationPreferencesSaveDiagnostics.userSaveMessage(for: error)
                    ExperienceHaptics.play(.error)
                    return
                }
                continue
            }
        }
    }

    private func mergeServerResponse(
        _ server: NotificationPreferences,
        appliedBatch: [NotificationPreferenceKey: Bool]
    ) {
        guard var current = preferences else {
            preferences = server
            return
        }
        for key in appliedBatch.keys where outbox[key] == nil {
            if let value = server.values[key] {
                current.values[key] = value
            }
        }
        current.updatedAt = server.updatedAt
        preferences = current
    }

    private func revertFailedBatch(
        _ batch: [NotificationPreferenceKey: Bool],
        snapshot: NotificationPreferences?,
        epochAtStart: UInt64
    ) {
        guard var current = preferences else { return }
        for (key, intended) in batch {
            if outbox[key] != nil {
                continue
            }
            if saveEpoch != epochAtStart {
                continue
            }
            if current.values[key] == intended {
                let rollback = snapshot?.values[key] ?? true
                current.values[key] = rollback
                outbox[key] = intended
            }
        }
        preferences = current
        if !outbox.isEmpty {
            // Caller will not auto-retry, user can toggle again; optional re-drain:
        }
    }
}