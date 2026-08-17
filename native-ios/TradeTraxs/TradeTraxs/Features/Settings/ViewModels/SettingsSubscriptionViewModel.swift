import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class SettingsSubscriptionViewModel {
    private let billing: any BillingRepository
    private let session: any SessionProviding

    private(set) var status: BillingStatus?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private var hasLoaded = false

    init(
        billing: any BillingRepository,
        session: any SessionProviding,
        navigationCoordinator _: NavigationCoordinator
    ) {
        self.billing = billing
        self.session = session
    }

    var planTitle: String {
        guard let status else { return "—" }
        switch status.lifecycle {
        case .trialing: return "TraxPro Trial"
        case .active where status.plan == .pro: return "TraxPro"
        case .pastDue: return "TraxPro (Past Due)"
        case .canceled: return "Canceled"
        case .expired: return "Expired"
        default: return status.plan == .pro ? "TraxPro" : "Free"
        }
    }

    var statusTitle: String {
        guard let status else { return "—" }
        switch status.lifecycle {
        case .trialing: return "Trialing"
        case .active: return "Active"
        case .pastDue: return "Past due"
        case .canceled: return "Canceled"
        case .expired: return "Expired"
        case .none: return status.isProEntitled ? "Active" : "Free"
        }
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        Task { await refresh() }
    }

    func refresh() async {
        isLoading = status == nil
        guard let userID = await session.currentUserID else {
            errorMessage = "Sign in to view your subscription."
            isLoading = false
            return
        }
        do {
            status = try await billing.status(for: ProfileID(userID.rawValue))
            errorMessage = nil
        } catch {
            // Development / offline: keep Settings usable with a Free baseline.
            if userID.rawValue.hasPrefix("dev.") {
                status = BillingStatus(
                    profileID: ProfileID(userID.rawValue),
                    plan: .free,
                    lifecycle: .none,
                    isProEntitled: false,
                    dailyTradeLimit: 10,
                    dailyPostLimit: 5,
                    dailyMessageLimit: 50,
                    maxTradeEntryAccounts: 3
                )
                errorMessage = nil
            } else {
                errorMessage = UserFacingError.message(for: error)
            }
        }
        isLoading = false
    }

    func openUpgrade() {
        ExperienceHaptics.play(.selection)
        // Native StoreKit upgrade is not shipped yet — open web pricing (same as web upsell).
        if let url = URL(string: "https://www.tradetraxs.com/pricing") {
            UIApplication.shared.open(url)
        }
    }
}
