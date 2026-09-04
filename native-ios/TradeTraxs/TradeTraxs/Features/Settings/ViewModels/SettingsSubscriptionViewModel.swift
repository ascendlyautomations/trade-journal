import Foundation
import Observation

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
        return status.hasTraxProAccess ? "TraxPro" : "Free"
    }

    var showsProMembership: Bool {
        status?.hasTraxProAccess == true
    }

    var showsFreePlanDetails: Bool {
        guard let status else { return false }
        return !status.hasTraxProAccess
    }

    var membershipSummaryFooter: String {
        guard let status else {
            return "Your plan details appear here when you're signed in."
        }
        if status.hasTraxProAccess {
            return "Your account has access to TraxPro features."
        }
        return "Your account is currently on the Free plan."
    }

    let traxProFeatureHighlights: [String] = [
        "Trade AI analysis on your trades",
        "Higher daily trade, post, and message limits",
        "More active trading accounts",
        "Advanced psychology and analytics tools",
    ]

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        Task { await refresh() }
    }

    func refresh() async {
        isLoading = status == nil
        guard let userID = await session.currentUserID else {
            errorMessage = "Sign in to view your plan."
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
}
