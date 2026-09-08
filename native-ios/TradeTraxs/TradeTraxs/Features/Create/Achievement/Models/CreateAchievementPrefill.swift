import Foundation

/// Production prefill for Add Achievement — e.g. after Record Payout.
nonisolated struct CreateAchievementPrefill: Hashable, Sendable {
    var kind: AchievementKind
    var titleText: String
    var descriptionText: String = ""
    var payoutAmountText: String
    var achievedAt: Date
    var selectedAccountID: TradingAccountID
    var isPublic: Bool
    var lockKind: Bool
}

@Observable
@MainActor
final class CreateAchievementPrefillStore {
    static let shared = CreateAchievementPrefillStore()

    private(set) var pending: CreateAchievementPrefill?

    private init() {}

    func stage(_ prefill: CreateAchievementPrefill) {
        pending = prefill
    }

    func consume() -> CreateAchievementPrefill? {
        defer { pending = nil }
        return pending
    }

    func clear() {
        pending = nil
    }
}
