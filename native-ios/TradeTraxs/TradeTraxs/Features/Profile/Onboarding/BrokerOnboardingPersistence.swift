import Foundation

/// Local per-profile state for the optional post-profile broker onboarding step.
enum BrokerOnboardingPersistence {
    private static let finishedKeyPrefix = "brokerOnboarding.finished."

    enum Status: Equatable, Sendable {
        /// New profile setup just finished — show broker onboarding once.
        case pending
        /// User skipped, connected, or was grandfathered before this feature existed.
        case finished
        /// No local record (existing profile before broker onboarding shipped).
        case unknown
    }

    static func status(for profileID: ProfileID) -> Status {
        if isFinished(profileID) { return .finished }
        if UserDefaults.standard.bool(forKey: pendingKey(profileID)) { return .pending }
        return .unknown
    }

    static func markPending(_ profileID: ProfileID) {
        UserDefaults.standard.set(true, forKey: pendingKey(profileID))
        UserDefaults.standard.removeObject(forKey: finishedKey(profileID))
    }

    static func markFinished(_ profileID: ProfileID) {
        UserDefaults.standard.set(true, forKey: finishedKey(profileID))
        UserDefaults.standard.removeObject(forKey: pendingKey(profileID))
    }

    static func grandfatherExistingProfileIfNeeded(_ profileID: ProfileID) {
        guard status(for: profileID) == .unknown else { return }
        markFinished(profileID)
    }

    private static func isFinished(_ profileID: ProfileID) -> Bool {
        UserDefaults.standard.bool(forKey: finishedKey(profileID))
    }

    private static func pendingKey(_ profileID: ProfileID) -> String {
        "brokerOnboarding.pending.\(profileID.rawValue)"
    }

    private static func finishedKey(_ profileID: ProfileID) -> String {
        finishedKeyPrefix + profileID.rawValue
    }
}
