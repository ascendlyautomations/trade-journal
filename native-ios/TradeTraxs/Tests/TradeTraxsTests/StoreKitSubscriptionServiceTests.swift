import XCTest
@testable import TradeTraxs

final class StoreKitSubscriptionServiceTests: XCTestCase {
    override func tearDown() {
        IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled = false
        super.tearDown()
    }

    func testSyncRequestSendsSignedTransactionAndTransactionId() throws {
        let request = AppleSubscriptionSyncRequest(
            transactionId: "2000000123456789",
            signedTransactionInfo: "header.payload.signature"
        )
        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(object["transactionId"], "2000000123456789")
        XCTAssertEqual(object["signedTransactionInfo"], "header.payload.signature")
        XCTAssertNil(object["productId"])
        XCTAssertNil(object["isPro"])
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
    func sync(transactionID: String, signedTransactionInfo: String) async throws -> AppleSubscriptionSyncResponse {
        _ = transactionID
        _ = signedTransactionInfo
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
