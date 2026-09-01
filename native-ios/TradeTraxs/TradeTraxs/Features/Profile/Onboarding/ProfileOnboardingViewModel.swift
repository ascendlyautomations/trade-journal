import Foundation
import Observation

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

    private(set) var displayName: String = ""
    private let snapshot: ProfileOnboardingSnapshot
    private let profiles: any ProfileRepository
    private let gateStore: ProfileOnboardingGateStore

    init(
        snapshot: ProfileOnboardingSnapshot,
        profiles: any ProfileRepository,
        gateStore: ProfileOnboardingGateStore
    ) {
        self.snapshot = snapshot
        self.profiles = profiles
        self.gateStore = gateStore
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
    }

    var canSubmit: Bool {
        !isSubmitting
            && ProfileUsernamePolicy.validateNotEmpty(username) == nil
            && !tradingStyle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && traderType != nil
            && !startedTrading.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !StartedTradingDatePolicy.isFuture(startedTrading)
    }

    func submit() async {
        guard canSubmit else { return }
        errorMessage = nil

        if let usernameError = ProfileUsernamePolicy.validateNotEmpty(username) {
            errorMessage = usernameError
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
            if try await profiles.isUsernameTaken(normalizedUsername, excluding: snapshot.profileID) {
                errorMessage = "Username already in use"
                ExperienceHaptics.play(.warning)
                return
            }

            let submission = ProfileOnboardingSubmission(
                profileID: snapshot.profileID,
                username: normalizedUsername,
                displayName: displayName.nonEmptyOrNil,
                bio: bio.nonEmptyOrNil,
                tradingStyle: tradingStyle.trimmingCharacters(in: .whitespacesAndNewlines),
                traderType: traderType,
                startedTrading: String(startedTrading.prefix(10)),
                avatarURL: snapshot.avatarURL,
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
                avatarURL: snapshot.avatarURL
            )
            gateStore.markCompleted(with: profile, snapshot: completedSnapshot)
            ExperienceHaptics.play(.success)
        } catch {
            if ProfileUsernamePolicy.isProfilesUsernameConflict(error) {
                errorMessage = "Username already in use"
            } else {
                errorMessage = UserFacingError.message(for: error)
            }
            ExperienceHaptics.play(.warning)
        }
    }
}

private extension String {
    var nonEmptyOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
