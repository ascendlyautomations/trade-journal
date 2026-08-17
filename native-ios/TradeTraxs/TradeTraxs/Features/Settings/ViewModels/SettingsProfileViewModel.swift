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
    private var hasLoaded = false

    init(
        profiles: any ProfileRepository,
        session: any SessionProviding,
        profileStore: CurrentUserProfileStore? = nil
    ) {
        self.profiles = profiles
        self.session = session
        self.profileStore = profileStore
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        Task { await refresh() }
    }

    func refresh() async {
        isLoading = profile == nil
        do {
            guard let userID = await session.currentUserID else {
                errorMessage = "Sign in to continue."
                isLoading = false
                return
            }
            let loaded = try await profiles.profile(id: ProfileID(userID.rawValue))
            apply(loaded)
            errorMessage = nil
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
        isLoading = false
    }

    func save() {
        guard var current = profile else { return }
        current.displayName = draftDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        current.bio = draftBio.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        current.tradingStyle = draftTradingStyle.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        current.primaryMarket = draftPrimaryMarket.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        current.isPrivate = draftIsPrivate

        Task {
            do {
                let updated = try await profiles.updateProfile(current)
                apply(updated)
                profileStore?.refresh()
                saveMessage = "Profile saved"
                ExperienceHaptics.play(.success)
            } catch {
                errorMessage = UserFacingError.message(for: error)
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
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
