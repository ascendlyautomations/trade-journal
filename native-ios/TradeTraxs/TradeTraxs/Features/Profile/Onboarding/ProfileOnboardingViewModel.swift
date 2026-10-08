import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class ProfileOnboardingViewModel {
    var username = ""
    var tradingStyle = ""
    var primaryMarket = ""
    var traderType: TraderType?
    var startedTrading = StartedTradingDatePolicy.localTodayInput()
    var bio = ""
    var isSubmitting = false
    var errorMessage: String?
    var displayNameError: String?
    var usernameError: String?
    var avatarPreview: UIImage?
    var avatarUploadError: String?

    var displayName: String = ""
    private(set) var prefilledAvatarReference: MediaReference?

    private var pendingAvatarData: Data?
    private var existingAvatarURL: String?

    private let snapshot: ProfileOnboardingSnapshot
    private let profiles: any ProfileRepository
    private let gateStore: ProfileOnboardingGateStore
    private let uploadService: UploadService
    private let objectStorage: any ObjectStorageProviding
    private let appConfiguration: AppConfiguration

    init(
        snapshot: ProfileOnboardingSnapshot,
        profiles: any ProfileRepository,
        gateStore: ProfileOnboardingGateStore,
        uploadService: UploadService,
        objectStorage: any ObjectStorageProviding,
        appConfiguration: AppConfiguration
    ) {
        self.snapshot = snapshot
        self.profiles = profiles
        self.gateStore = gateStore
        self.uploadService = uploadService
        self.objectStorage = objectStorage
        self.appConfiguration = appConfiguration
        self.displayName = ProfileOnboardingNamePrefill.editableName(
            snapshot: snapshot,
            userID: UserID(snapshot.profileID.rawValue)
        )
        self.username = ProfileUsernamePolicy.onboardingPrefillUsername(
            current: snapshot.username,
            profileID: snapshot.profileID
        )
        self.tradingStyle = snapshot.tradingStyle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.primaryMarket = snapshot.primaryMarket?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let parsed = TraderType.parse(snapshot.traderType) {
            self.traderType = parsed
        }
        if let started = snapshot.startedTrading?.trimmingCharacters(in: .whitespacesAndNewlines),
           !started.isEmpty,
           started.count >= 10 {
            self.startedTrading = String(started.prefix(10))
        }
        self.bio = ProfileBioPolicy.constrained(
            snapshot.bio?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
        self.existingAvatarURL = snapshot.avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil
        if let existingAvatarURL {
            prefilledAvatarReference = MediaReference(id: existingAvatarURL, kind: .image, altText: nil)
        }
    }

    var canSubmit: Bool {
        !isSubmitting
            && ProfileDisplayNamePolicy.validateRequired(displayName) == nil
            && ProfileUsernamePolicy.validateNotEmpty(username) == nil
            && !tradingStyle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && traderType != nil
            && !startedTrading.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !StartedTradingDatePolicy.isFuture(startedTrading)
    }

    var canContinueWithoutPhoto: Bool {
        avatarUploadError != nil && pendingAvatarData != nil
    }

    func clearUsernameError() {
        usernameError = nil
    }

    /// Fills a blank Name field from the saved profile, then the Create Account name. Edits stay.
    func applySignupNamePrefillIfBlank() {
        guard ProfileDisplayNamePolicy.normalized(displayName) == nil else { return }
        let prefilled = ProfileOnboardingNamePrefill.editableName(
            snapshot: snapshot,
            userID: UserID(snapshot.profileID.rawValue)
        )
        guard !prefilled.isEmpty else { return }
        displayName = prefilled
    }

    func setAvatarImage(_ image: UIImage?) {
        avatarUploadError = nil
        guard let image else {
            avatarPreview = nil
            pendingAvatarData = nil
            return
        }
        avatarPreview = image
        pendingAvatarData = MediaImagePreparation.avatarJPEGData(from: image)
        if pendingAvatarData == nil {
            avatarUploadError = "Couldn't prepare that photo. Try a different image."
            avatarPreview = nil
        }
    }

    func clearAvatarSelection() {
        setAvatarImage(nil)
        avatarUploadError = nil
        prefilledAvatarReference = nil
    }

    func continueWithoutPhoto() async {
        await submit(skipPendingAvatar: true)
    }

    func submit(skipPendingAvatar: Bool = false) async {
        guard !isSubmitting else { return }
        guard canSubmit else { return }

        errorMessage = nil
        displayNameError = nil
        usernameError = nil
        if !skipPendingAvatar {
            avatarUploadError = nil
        }

        if let nameValidationError = ProfileDisplayNamePolicy.validateRequired(displayName) {
            displayNameError = nameValidationError
            return
        }
        if let usernameValidationError = ProfileUsernamePolicy.validateNotEmpty(username) {
            usernameError = usernameValidationError
            return
        }
        if StartedTradingDatePolicy.isFuture(startedTrading) {
            errorMessage = "Started trading date cannot be in the future."
            return
        }
        guard let traderType else {
            errorMessage = "Trader type is required."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        let normalizedUsername = ProfileUsernamePolicy.normalize(username)
        var uploadedAvatarThisAttempt: String?

        do {
            var avatarURL = existingAvatarURL
            if let pendingAvatarData, !skipPendingAvatar {
                do {
                    avatarURL = try await uploadAvatar(pendingAvatarData)
                    uploadedAvatarThisAttempt = avatarURL
                } catch {
                    ProfileOnboardingErrorMapping.debugStage("avatar.upload", error: error)
                    avatarUploadError = ProfileOnboardingErrorMapping.avatarUploadMessage(for: error)
                    ExperienceHaptics.play(.warning)
                    return
                }
            } else if skipPendingAvatar {
                pendingAvatarData = nil
                avatarUploadError = nil
            }

            let trimmedPrimaryMarket = primaryMarket.trimmingCharacters(in: .whitespacesAndNewlines)
            let submission = ProfileOnboardingSubmission(
                profileID: snapshot.profileID,
                username: normalizedUsername,
                displayName: ProfileDisplayNamePolicy.normalized(displayName),
                bio: ProfileBioPolicy.persisted(bio),
                tradingStyle: tradingStyle.trimmingCharacters(in: .whitespacesAndNewlines),
                traderType: traderType,
                startedTrading: String(startedTrading.prefix(10)),
                avatarURL: avatarURL,
                primaryMarket: trimmedPrimaryMarket.isEmpty ? nil : trimmedPrimaryMarket
            )

            let profile = try await profiles.completeProfileOnboarding(submission)
            let completedSnapshot = ProfileOnboardingSnapshot(
                profileID: snapshot.profileID,
                username: profile.username,
                displayName: profile.displayName,
                onboardingCompleted: true,
                traderType: profile.traderType?.rawValue,
                tradingStyle: profile.tradingStyle,
                primaryMarket: profile.primaryMarket,
                startedTrading: submission.startedTrading,
                bio: profile.bio,
                avatarURL: avatarURL
            )
            gateStore.markCompleted(
                with: profile,
                snapshot: completedSnapshot,
                avatarPreview: avatarPreview
            )
            pendingAvatarData = nil
            existingAvatarURL = avatarURL
            ExperienceHaptics.play(.success)
        } catch {
            if let uploadedAvatarThisAttempt, uploadedAvatarThisAttempt != existingAvatarURL {
                await OwnedMediaStorageCleanup.removeReplacedObject(
                    previous: uploadedAvatarThisAttempt,
                    current: nil,
                    storage: objectStorage
                )
            }
            ProfileOnboardingErrorMapping.debugStage("completeProfileOnboarding", error: error)
            if ProfileUsernamePolicy.isProfilesUsernameConflict(error) {
                usernameError = ProfileOnboardingErrorMapping.usernameConflictMessage
            } else {
                errorMessage = ProfileOnboardingErrorMapping.submitMessage(for: error)
            }
            ExperienceHaptics.play(.warning)
        }
    }

    private func uploadAvatar(_ data: Data) async throws -> String {
        try await ProfileAvatarUpload.upload(
            jpegData: data,
            profileID: snapshot.profileID,
            uploadService: uploadService,
            objectStorage: objectStorage,
            supabaseURL: appConfiguration.supabaseURL
        )
    }
}

private extension String {
    var nonEmptyOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
