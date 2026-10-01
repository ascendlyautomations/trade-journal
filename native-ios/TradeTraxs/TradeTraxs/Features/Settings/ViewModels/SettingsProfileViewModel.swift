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
    private(set) var isSaving = false

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
        guard let profile, !isSaving else { return }
        errorMessage = nil
        usernameError = nil

        let normalizedUsername = ProfileUsernamePolicy.normalize(draftUsername)
        if let validationError = ProfileUsernamePolicy.validateNotEmpty(normalizedUsername) {
            usernameError = validationError
            return
        }

        let usernameChanged = !ProfileUsernamePolicy.profileUsernamesEqual(
            persistedUsername,
            normalizedUsername
        )
        #if DEBUG
        print(
            "[PROFILE_USERNAME] saveBegin old=\(ProfileUsernamePolicy.normalize(persistedUsername)) " +
                "new=\(normalizedUsername) changed=\(usernameChanged)"
        )
        #endif
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

        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let updated = try await profiles.updateProfileSettings(update)
                if usernameChanged,
                   !ProfileUsernamePolicy.profileUsernamesEqual(
                       ProfileUsernamePolicy.normalize(updated.username),
                       normalizedUsername
                   )
                {
                    usernameError = "Username could not be updated. Try again."
                    ExperienceHaptics.play(.warning)
                    return
                }
                commitConfirmedProfileMutation(updated)
                SaveSuccessConfirmationCenter.shared.present(SaveSuccessToastMessage.profileUpdated)
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
                commitConfirmedProfileMutation(updated)
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
                commitConfirmedProfileMutation(updated)
            } catch {
                draftTraderType = previous
                profile?.traderType = previous
                errorMessage = "Couldn't update trader type."
                ExperienceHaptics.play(.warning)
            }
        }
    }

    func persistCroppedAvatar(_ image: UIImage) {
        guard !isUploadingAvatar else { return }
        avatarUploadError = nil
        avatarPreview = image
        guard let profile else { return }

        guard let uploadService, let objectStorage else {
            avatarUploadError = "Photo upload isn't available right now."
            avatarPreview = nil
            return
        }

        guard let jpegData = MediaImagePreparation.avatarJPEGData(from: image) else {
            avatarUploadError = "Couldn't prepare that photo. Try a different image."
            avatarPreview = nil
            return
        }

        let profileID = profile.id
        let previousAvatarURL = profile.avatar?.id

        isUploadingAvatar = true
        Task {
            defer { isUploadingAvatar = false }
            var uploadedURL: String?
            do {
                let avatarURL = try await ProfileAvatarUpload.upload(
                    jpegData: jpegData,
                    profileID: profileID,
                    uploadService: uploadService,
                    objectStorage: objectStorage,
                    supabaseURL: supabaseURL
                )
                uploadedURL = avatarURL
                guard var updatedProfile = self.profile else {
                    await OwnedMediaStorageCleanup.removeReplacedObject(
                        previous: avatarURL,
                        current: nil,
                        storage: objectStorage
                    )
                    avatarPreview = nil
                    return
                }
                updatedProfile.avatar = MediaReference(id: avatarURL, kind: .image, altText: nil)
                let saved = try await profiles.updateProfile(updatedProfile)
                await OwnedMediaStorageCleanup.removeReplacedObject(
                    previous: previousAvatarURL,
                    current: avatarURL,
                    storage: objectStorage
                )
                commitConfirmedProfileMutation(saved, localAvatar: image)
                avatarPreview = nil
                SaveSuccessConfirmationCenter.shared.present(SaveSuccessToastMessage.profileUpdated)
                ExperienceHaptics.play(.success)
            } catch {
                avatarPreview = nil
                if let uploadedURL {
                    await OwnedMediaStorageCleanup.removeReplacedObject(
                        previous: uploadedURL,
                        current: nil,
                        storage: objectStorage
                    )
                }
                avatarUploadError = ProfileOnboardingErrorMapping.avatarUploadMessage(for: error)
                ExperienceHaptics.play(.warning)
            }
        }
    }

    private func commitConfirmedProfileMutation(_ updated: Profile, localAvatar: UIImage? = nil) {
        apply(updated)
        profileStore?.applyConfirmedOwnerProfile(updated, localAvatar: localAvatar)
    }

    private func apply(_ profile: Profile) {
        let preserveUsernameDraft = !ProfileUsernamePolicy.profileUsernamesEqual(
            persistedUsername,
            ProfileUsernamePolicy.normalize(draftUsername)
        )
        let inFlightUsernameDraft = draftUsername

        self.profile = profile
        draftDisplayName = profile.displayName
        draftBio = profile.bio ?? ""
        draftTradingStyle = profile.tradingStyle ?? ""
        draftPrimaryMarket = profile.primaryMarket ?? ""
        draftIsPrivate = profile.isPrivate
        draftTraderType = profile.traderType
        usernameChangeCount = profile.usernameChangeCount
        persistedUsername = profile.username
        if preserveUsernameDraft {
            draftUsername = inFlightUsernameDraft
        } else {
            draftUsername = ProfileUsernamePolicy.sanitizeForTyping(profile.username)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
