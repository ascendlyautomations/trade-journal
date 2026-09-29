import XCTest
@testable import TradeTraxs

final class StoreKitSubscriptionServiceTests: XCTestCase {
    override func tearDown() {
        IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled = false
        super.tearDown()
    }

    func testIosPaidSubscriptionsDisabledSkipsOfferCodePresentation() async {
        IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled = false
        let service = StoreKitSubscriptionService(syncClient: RecordingAppleSyncClient())
        do {
            try await service.presentOfferCodeRedemption()
        } catch {
            XCTFail("Expected no throw when paywall disabled")
        }
    }
}

private struct RecordingAppleSyncClient: AppleSubscriptionSyncClienting {
    func sync(transactionID: String) async throws -> AppleSubscriptionSyncResponse {
        _ = transactionID
        return AppleSubscriptionSyncResponse(
            traxProActive: false,
            source: nil,
            productId: nil,
            billingInterval: nil,
            expiresAt: nil,
            appleSubscriptionStatus: nil
        )
    }

    func fetchEntitlement() async throws -> BillingEntitlementResponse {
        BillingEntitlementResponse(
            traxProActive: false,
            source: nil,
            plan: nil,
            billingInterval: nil,
            subscriptionStatus: nil,
            trialEndsAt: nil,
            currentPeriodEndsAt: nil,
            cancelAtPeriodEnd: nil,
            appleExpiresAt: nil,
            appleProductId: nil
        )
    }

    func fetchMonetizationConfig() async throws -> IosMonetizationConfigResponse {
        let data = Data("""
        {"iosPaywallEnabled":false,"entitlementEnforcementEnabled":false}
        """.utf8)
        return try JSONDecoder().decode(IosMonetizationConfigResponse.self, from: data)
    }
}
