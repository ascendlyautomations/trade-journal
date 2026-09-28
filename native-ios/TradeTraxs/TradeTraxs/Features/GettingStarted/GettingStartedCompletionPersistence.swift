import Foundation

/// Per-user monotonic Getting Started completion mirror (device-local, fast restore).
enum GettingStartedCompletionPersistence {
    private static let keyBase = "tradetraxs_getting_started_completion_v1"

    static func load(userID: String) -> GettingStartedSignals {
        let key = storageKey(userID: userID)
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(GettingStartedPersistedWire.self, from: data)
        else {
            return .empty
        }
        return decoded.signals
    }

    static func save(userID: String, signals: GettingStartedSignals) {
        let key = storageKey(userID: userID)
        let wire = GettingStartedPersistedWire(from: signals)
        guard let data = try? JSONEncoder().encode(wire) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear(userID: String) {
        UserDefaults.standard.removeObject(forKey: storageKey(userID: userID))
    }

    private static func storageKey(userID: String) -> String {
        "\(keyBase):\(userID)"
    }

    private struct GettingStartedPersistedWire: Codable {
        var onboardingCompleted: Bool
        var hasSeenGettingStartedIntro: Bool
        var hasSeenOnboardingCompletePopup: Bool
        var tradeCount: Int
        var hasCreatedProfilePost: Bool?
        var profilePostCount: Int
        var followCount: Int
        var hasEverJoinedOtherRoom: Bool
        var hasPublicTrade: Bool
        var hasCompletedDailyCheckIn: Bool
        var firstPrivateTradeID: String?

        init(from signals: GettingStartedSignals) {
            onboardingCompleted = signals.onboardingCompleted
            hasSeenGettingStartedIntro = signals.hasSeenGettingStartedIntro
            hasSeenOnboardingCompletePopup = signals.hasSeenOnboardingCompletePopup
            tradeCount = signals.tradeCount
            hasCreatedProfilePost = signals.hasCreatedProfilePost
            profilePostCount = signals.profilePostCount
            followCount = signals.followCount
            hasEverJoinedOtherRoom = signals.hasEverJoinedOtherRoom
            hasPublicTrade = signals.hasPublicTrade
            hasCompletedDailyCheckIn = signals.hasCompletedDailyCheckIn
            firstPrivateTradeID = signals.firstPrivateTradeID?.rawValue
        }

        var signals: GettingStartedSignals {
            GettingStartedSignals(
                onboardingCompleted: onboardingCompleted,
                hasSeenGettingStartedIntro: hasSeenGettingStartedIntro,
                hasSeenOnboardingCompletePopup: hasSeenOnboardingCompletePopup,
                tradeCount: max(0, tradeCount),
                hasCreatedProfilePost: hasCreatedProfilePost == true || profilePostCount > 0,
                profilePostCount: max(0, profilePostCount),
                followCount: max(0, followCount),
                hasEverJoinedOtherRoom: hasEverJoinedOtherRoom,
                hasPublicTrade: hasPublicTrade,
                hasCompletedDailyCheckIn: hasCompletedDailyCheckIn,
                firstPrivateTradeID: firstPrivateTradeID.flatMap { TradeID($0) }
            )
        }
    }
}
