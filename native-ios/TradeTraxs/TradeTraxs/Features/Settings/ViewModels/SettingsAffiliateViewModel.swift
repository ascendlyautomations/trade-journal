import Foundation
import Observation

@Observable
@MainActor
final class SettingsAffiliateViewModel {
    private let referrals: any ReferralRepository
    private let session: any SessionProviding

    private(set) var referral: Referral?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private var hasLoaded = false

    init(referrals: any ReferralRepository, session: any SessionProviding) {
        self.referrals = referrals
        self.session = session
    }

    var referralLink: URL? {
        guard let code = referral?.code, !code.isEmpty else { return nil }
        return URL(string: "https://www.tradetraxs.com/?ref=\(code)")
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        Task { await refresh() }
    }

    func refresh() async {
        isLoading = referral == nil
        do {
            guard let userID = await session.currentUserID else {
                errorMessage = "Not signed in"
                isLoading = false
                return
            }
            referral = try await referrals.referral(for: ProfileID(userID.rawValue))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
