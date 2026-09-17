import Foundation
import Observation

@Observable
@MainActor
final class SettingsProfileViewModel {
    private let profiles: any ProfileRepository
    private let session: any SessionProviding
    private let profileStore: CurrentUserProfileStore?

    private(set) var profile: Profile?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var saveMessage: String?
    var draftDisplayName = ""
    var draftBio = ""
    var draftTradingStyle = ""
    var draftPrimaryMarket = ""
    var draftIsPrivate = false
    var draftUsername = ""
    var usernameError: String?

    private(set) var usernameChangeCount = 0
    private var persistedUsername = ""

    init(
        profiles: any ProfileRepository,
        session: any SessionProviding,
        profileStore: CurrentUserProfileStore? = nil
    ) {
        self.profiles = profiles
        self.session = session
        self.profileStore = profileStore
    }

    var remainingUsernameChanges: Int {
        ProfileUsernameChangePolicy.changesRemaining(changeCount: usernameChangeCount)
    }

    var atUsernameChangeLimit: Bool {
        !ProfileUsernameChangePolicy.canChangeProfileUsername(changeCount: usernameChangeCount)
    }

    func loadIfNeeded() {
        if let cached = profileStore?.profile {
            apply(cached)
        }
        Task { await refresh() }
    }

    func refresh() async {
        if profile == nil, let cached = profileStore?.profile {
            apply(cached)
        }
        isLoading = profile == nil
        do {
            guard let userID = await session.currentUserID else {
                errorMessage = "Sign in to continue."
                isLoading = false
                return
            }
            let loaded = try await profiles.ownerProfileForSettings(id: ProfileID(userID.rawValue))
            apply(loaded)
            errorMessage = nil
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
        isLoading = false
    }

    func clearUsernameError() {
        usernameError = nil
    }

    func save() {
        guard let profile else { return }
        errorMessage = nil
        usernameError = nil
        saveMessage = nil

        let normalizedUsername = ProfileUsernamePolicy.normalize(draftUsername)
        if let validationError = ProfileUsernamePolicy.validateNotEmpty(normalizedUsername) {
            usernameError = validationError
            return
        }

        let usernameChanged = !ProfileUsernamePolicy.profileUsernamesEqual(
            persistedUsername,
            normalizedUsername
        )
        if usernameChanged, atUsernameChangeLimit {
            usernameError = "Maximum username changes reached."
            return
        }

        let update = ProfileSettingsUpdate(
            profileID: profile.id,
            displayName: draftDisplayName.trimmingCharacters(in: .whitespacesAndNewlines),
            bio: draftBio.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            tradingStyle: draftTradingStyle.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            primaryMarket: draftPrimaryMarket.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            isPrivate: draftIsPrivate,
            username: normalizedUsername,
            persistedUsername: persistedUsername,
            usernameChangeCount: usernameChangeCount
        )

        Task {
            do {
                let updated = try await profiles.updateProfileSettings(update)
                apply(updated)
                profileStore?.refresh()
                saveMessage = "Profile saved"
                ExperienceHaptics.play(.success)
            } catch {
                let message = UserFacingError.message(for: error)
                if usernameChanged || message.localizedCaseInsensitiveContains("username") {
                    usernameError = message
                } else {
                    errorMessage = message
                }
                ExperienceHaptics.play(.warning)
            }
        }
    }

    func setPrivate(_ value: Bool) {
        draftIsPrivate = value
        guard var current = profile, current.isPrivate != value else { return }
        let previous = current.isPrivate
        current.isPrivate = value
        profile = current
        Task {
            do {
                let updated = try await profiles.updateProfile(current)
                apply(updated)
                profileStore?.refresh()
                saveMessage = nil
            } catch {
                draftIsPrivate = previous
                profile?.isPrivate = previous
                errorMessage = "Couldn't update privacy setting."
                ExperienceHaptics.play(.warning)
            }
        }
    }

    private func apply(_ profile: Profile) {
        self.profile = profile
        draftDisplayName = profile.displayName
        draftBio = profile.bio ?? ""
        draftTradingStyle = profile.tradingStyle ?? ""
        draftPrimaryMarket = profile.primaryMarket ?? ""
        draftIsPrivate = profile.isPrivate
        usernameChangeCount = profile.usernameChangeCount
        persistedUsername = profile.username
        draftUsername = ProfileUsernamePolicy.sanitizeForTyping(profile.username)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
