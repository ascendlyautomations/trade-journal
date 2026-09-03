import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class ProfileOnboardingViewModel {
    var username = ""
    var tradingStyle = ""
    var traderType: TraderType?
    var startedTrading = StartedTradingDatePolicy.localTodayInput()
    var bio = ""
    var isSubmitting = false
    var errorMessage: String?
    var usernameError: String?
    var avatarPreview: UIImage?
    var avatarUploadError: String?

    private(set) var displayName: String = ""

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
        self.displayName = ProfileDisplayNamePolicy.normalized(snapshot.displayName) ?? ""
        self.username = ProfileUsernamePolicy.onboardingPrefillUsername(
            current: snapshot.username,
            profileID: snapshot.profileID
        )
        self.tradingStyle = snapshot.tradingStyle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let parsed = TraderType.parse(snapshot.traderType) {
            self.traderType = parsed
        }
        if let started = snapshot.startedTrading?.trimmingCharacters(in: .whitespacesAndNewlines),
           !started.isEmpty,
           started.count >= 10 {
            self.startedTrading = String(started.prefix(10))
        }
        self.bio = snapshot.bio?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.existingAvatarURL = snapshot.avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil
    }

    var canSubmit: Bool {
        !isSubmitting
            && ProfileUsernamePolicy.validateNotEmpty(username) == nil
            && !tradingStyle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && traderType != nil
            && !startedTrading.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !StartedTradingDatePolicy.isFuture(startedTrading)
    }

    func clearUsernameError() {
        usernameError = nil
    }

    func setAvatarImage(_ image: UIImage?) {
        avatarUploadError = nil
        guard let image else {
            avatarPreview = nil
            pendingAvatarData = nil
            return
        }
        avatarPreview = image
        pendingAvatarData = MediaImagePreparation.jpegData(
            from: image,
            maxDimension: 1200,
            quality: 0.92
        )
        if pendingAvatarData == nil {
            avatarUploadError = "Couldn't prepare that photo. Try a different image."
            avatarPreview = nil
        }
    }

    func clearAvatarSelection() {
        setAvatarImage(nil)
        avatarUploadError = nil
    }

    func submit() async {
        guard !isSubmitting else { return }
        guard canSubmit else { return }

        errorMessage = nil
        usernameError = nil
        avatarUploadError = nil

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

        do {
            var avatarURL = existingAvatarURL
            if let pendingAvatarData {
                do {
                    avatarURL = try await uploadAvatar(pendingAvatarData)
                } catch {
                    ProfileOnboardingErrorMapping.debugStage("avatar.upload", error: error)
                    avatarUploadError = ProfileOnboardingErrorMapping.avatarUploadMessage(for: error)
                    ExperienceHaptics.play(.warning)
                    return
                }
            }

            let submission = ProfileOnboardingSubmission(
                profileID: snapshot.profileID,
                username: normalizedUsername,
                displayName: displayName.nonEmptyOrNil,
                bio: bio.nonEmptyOrNil,
                tradingStyle: tradingStyle.trimmingCharacters(in: .whitespacesAndNewlines),
                traderType: traderType,
                startedTrading: String(startedTrading.prefix(10)),
                avatarURL: avatarURL,
                primaryMarket: nil
            )

            let profile = try await profiles.completeProfileOnboarding(submission)
            let completedSnapshot = ProfileOnboardingSnapshot(
                profileID: snapshot.profileID,
                username: profile.username,
                displayName: profile.displayName,
                onboardingCompleted: true,
                traderType: profile.traderType?.rawValue,
                tradingStyle: profile.tradingStyle,
                startedTrading: submission.startedTrading,
                bio: profile.bio,
                avatarURL: avatarURL
            )
            gateStore.markCompleted(with: profile, snapshot: completedSnapshot)
            ExperienceHaptics.play(.success)
        } catch {
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
        let path = "\(snapshot.profileID.rawValue)/\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
        let reference = try await uploadService.upload(
            UploadRequest(
                bucket: StorageBucket.avatars.rawValue,
                path: path,
                data: data,
                contentType: "image/jpeg",
                purpose: .profileAvatar
            )
        )
        if let url = objectStorage.publicURL(
            bucket: StorageBucket.avatars.rawValue,
            path: reference.id
        )?.absoluteString {
            return url
        }
        if let base = appConfiguration.supabaseURL?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) {
            return "\(base)/storage/v1/object/public/avatars/\(reference.id)"
        }
        return reference.id
    }
}

private extension String {
    var nonEmptyOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
