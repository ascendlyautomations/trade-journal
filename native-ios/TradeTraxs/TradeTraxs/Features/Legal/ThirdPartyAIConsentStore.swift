import Foundation

/// Per-user first-use consent for sending data to OpenAI via TradeTraxs BFF.
enum ThirdPartyAIConsentStore {
    private static let consentedUserIDsKey = "tt.ai.thirdParty.openai.consentedUserIDs"

    static func hasConsent(for userID: UserID) -> Bool {
        consentedUserIDs().contains(userID.rawValue)
    }

    static func recordConsent(for userID: UserID) {
        var ids = consentedUserIDs()
        ids.insert(userID.rawValue)
        UserDefaults.standard.set(Array(ids), forKey: consentedUserIDsKey)
    }

    private static func consentedUserIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: consentedUserIDsKey) ?? [])
    }
}

enum ThirdPartyAIConsentError: Error, Sendable {
    case userDeclined
    case notAuthenticated
}
