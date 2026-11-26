import Foundation

@MainActor
enum TraxProEntitlementRefreshAction {
    static func refresh(data: DataEnvironment) async {
        guard let userID = await data.session.currentUserID else { return }
        let profileID = ProfileID(userID.rawValue)
        await BillingEntitlementRefreshFlight.shared.refresh {
            do {
                let refreshed = try await data.billing.refreshEntitlements(for: profileID)
                await MainActor.run {
                    SessionBillingEntitlementStore.shared.apply(refreshed)
                    NotificationCenter.default.post(
                        name: .billingEntitlementsDidRefresh,
                        object: refreshed
                    )
                    Task {
                        await PerformanceReportReminderCoordinator.shared.reconcile(profileID: profileID)
                    }
                }
            } catch {
                // Keep last-known snapshot; the verification UI stays until a later refresh succeeds.
            }
        }
    }
}