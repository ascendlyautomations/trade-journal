import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class SettingsProfileViewModel {
    private let profiles: any ProfileRepository
    private let session: any SessionProviding
    private let profileStore: CurrentUserProfileStore?
    private let uploadService: (any UploadService)?
    private let objectStorage: (any ObjectStorageProviding)?
    private let supabaseURL: URL?

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
    var draftTraderType: TraderType?
    var usernameError: String?

    private(set) var avatarPreview: UIImage?
    private(set) var avatarUploadError: String?
    private(set) var isUploadingAvatar = false

    private(set) var usernameChangeCount = 0
    private var persistedUsername = ""

    init(
        profiles: any ProfileRepository,
        session: any SessionProviding,
        profileStore: CurrentUserProfileStore? = nil,
        uploadService: (any UploadService)? = nil,
        objectStorage: (any ObjectStorageProviding)? = nil,
        supabaseURL: URL? = nil
    ) {
        self.profiles = profiles
        self.session = session
        self.profileStore = profileStore
        self.uploadService = uploadService
        self.objectStorage = objectStorage
        self.supabaseURL = supabaseURL
    }

    var remainingUsernameChanges: Int {
        ProfileUsernameChangePolicy.changesRemaining(changeCount: usernameChangeCount)
    }

    var atUsernameChangeLimit: Bool {
        !ProfileUsernameChangePolicy.canChangeProfileUsername(changeCount: usernameChangeCount)
    }

    var canChangeAvatar: Bool {
        uploadService != nil && objectStorage != nil && profile != nil
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

    func clearAvatarUploadError() {
        avatarUploadError = nil
    }

    func noteAvatarPhotoLoadFailed() {
        avatarUploadError = "Couldn't load that photo. Try another image."
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

        let traderTypeForUpdate: TraderType? = {
            guard let draftTraderType, draftTraderType != profile.traderType else { return nil }
            return draftTraderType
        }()

        let update = ProfileSettingsUpdate(
            profileID: profile.id,
            displayName: draftDisplayName.trimmingCharacters(in: .whitespacesAndNewlines),
            bio: draftBio.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            tradingStyle: draftTradingStyle.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            primaryMarket: draftPrimaryMarket.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            isPrivate: draftIsPrivate,
            username: normalizedUsername,
            persistedUsername: persistedUsername,
            usernameChangeCount: usernameChangeCount,
            traderType: traderTypeForUpdate
        )

        Task {
            do {
                let updated = try await profiles.updateProfileSettings(update)
                apply(updated)
                profileStore?.adoptDisplayedAvatar(from: updated)
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
                profileStore?.adoptDisplayedAvatar(from: updated)
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

    func setTraderType(_ type: TraderType) {
        guard draftTraderType != type else { return }
        draftTraderType = type
        guard var current = profile else { return }
        let previous = current.traderType
        guard previous != type else { return }
        current.traderType = type
        profile = current
        Task {
            do {
                let updated = try await profiles.updateProfile(current)
                apply(updated)
                profileStore?.adoptDisplayedAvatar(from: updated)
                profileStore?.refresh()
                saveMessage = nil
            } catch {
                draftTraderType = previous
                profile?.traderType = previous
                errorMessage = "Couldn't update trader type."
                ExperienceHaptics.play(.warning)
            }
        }
    }

    func persistCroppedAvatar(_ image: UIImage) {
        avatarUploadError = nil
        avatarPreview = image
        guard let profile else { return }
        profileStore?.installLocalAvatar(image, avatarID: profile.avatar?.id ?? "pending-avatar")

        guard let uploadService, let objectStorage else {
            avatarUploadError = "Photo upload isn't available right now."
            return
        }

        guard let jpegData = MediaImagePreparation.jpegData(from: image, maxDimension: 1200, quality: 0.92) else {
            avatarUploadError = "Couldn't prepare that photo. Try a different image."
            avatarPreview = nil
            return
        }

        let profileID = profile.id

        isUploadingAvatar = true
        Task {
            defer { isUploadingAvatar = false }
            do {
                let avatarURL = try await ProfileAvatarUpload.upload(
                    jpegData: jpegData,
                    profileID: profileID,
                    uploadService: uploadService,
                    objectStorage: objectStorage,
                    supabaseURL: supabaseURL
                )
                guard var updatedProfile = self.profile else { return }
                updatedProfile.avatar = MediaReference(id: avatarURL, kind: .image, altText: nil)
                let saved = try await profiles.updateProfile(updatedProfile)
                apply(saved)
                profileStore?.installLocalAvatar(image, avatarID: avatarURL)
                profileStore?.adoptDisplayedAvatar(from: saved)
                profileStore?.refresh()
                avatarPreview = nil
                saveMessage = nil
                ExperienceHaptics.play(.success)
            } catch {
                avatarUploadError = ProfileOnboardingErrorMapping.avatarUploadMessage(for: error)
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
        draftTraderType = profile.traderType
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
