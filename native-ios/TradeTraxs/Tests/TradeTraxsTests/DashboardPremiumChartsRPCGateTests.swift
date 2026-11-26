import Foundation
import Testing
@testable import TradeTraxs

private struct PremiumChartsRPCMustNotRun: RPCClient {
    func call(functionName: String, parameters: [String: String]) async throws -> Data {
        Issue.record("Premium chart RPC must not run for gated caller")
        throw AppError.unknown(message: "unexpected rpc")
    }

    func call(functionName: String, jsonBody: Data) async throws -> Data {
        Issue.record("Premium chart RPC must not run for gated caller")
        throw AppError.unknown(message: "unexpected rpc")
    }
}

@MainActor
struct DashboardPremiumChartsRPCGateTests {
    private let freeProfile = ProfileID("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
    private let liveAccount = TradingAccountID("11111111-1111-4111-8111-111111111111")

    @Test("BackendV2 premium analytics denial is non-retryable")
    func backendV2PremiumAnalyticsRequiredDoesNotRetry() {
        let detail = PostgRESTValidationDetail(
            httpStatus: 400,
            code: "P0001",
            message: "TRAXPRO_PREMIUM_ANALYTICS_REQUIRED",
            details: nil,
            hint: "Advanced performance analytics are available with TraxPro."
        )
        let error = BackendV2RPCError.requestValidation(detail)
        #expect(DashboardAnalyticsChartsFailurePolicy.isPremiumAnalyticsEntitlementDenial(error))
        #expect(DashboardAnalyticsChartsFailurePolicy.shouldNotRetry(error))
        #expect(ProGateReasonParser.feature(from: error) == .premiumAnalytics)
    }

    @Test("Unrelated P0001 remains retryable")
    func unrelatedP0001IsRetryable() {
        let detail = PostgRESTValidationDetail(
            httpStatus: 400,
            code: "P0001",
            message: "pin_limit_reached",
            details: nil,
            hint: nil
        )
        let error = BackendV2RPCError.requestValidation(detail)
        #expect(!DashboardAnalyticsChartsFailurePolicy.isPremiumAnalyticsEntitlementDenial(error))
        #expect(!DashboardAnalyticsChartsFailurePolicy.shouldNotRetry(error))
    }

    @Test("Free user does not invoke aggregate premium charts RPC")
    func freeUserSkipsAggregateChartsRPC() async {
        IosSubscriptionReleaseConfiguration.setTestOverrides(paywall: true, enforcement: true)
        PersistedEntitlementSnapshotStore.save(
            EntitlementSnapshotRecord(
                userID: freeProfile.rawValue,
                traxProActive: false,
                source: "none",
                accessExpiresAt: nil,
                revokedAt: nil,
                fetchedAt: Date()
            )
        )
        defer {
            PersistedEntitlementSnapshotStore.clear(userID: freeProfile.rawValue)
            IosSubscriptionReleaseConfiguration.resetTestOverrides()
            DashboardAnalyticsAggregateChartsStore.shared.invalidate()
        }

        DashboardAnalyticsAggregateChartsStore.shared.invalidate()
        let revision: Int64 = 12
        let token = DashboardAnalyticsAggregateChartsCoordinator.bumpSelection()
        let applied = await DashboardAnalyticsAggregateChartsCoordinator.loadIfNeeded(
            selectionToken: token,
            revision: revision,
            viewerID: freeProfile,
            rpc: PremiumChartsRPCMustNotRun()
        )
        #expect(!applied)
        #expect(
            DashboardAnalyticsAggregateChartsStore.shared.availability(revision: revision)
                == .failedNonRetryable
        )
    }

    @Test("Free user does not invoke account premium charts RPC")
    func freeUserSkipsAccountChartsRPC() async {
        IosSubscriptionReleaseConfiguration.setTestOverrides(paywall: true, enforcement: true)
        PersistedEntitlementSnapshotStore.save(
            EntitlementSnapshotRecord(
                userID: freeProfile.rawValue,
                traxProActive: false,
                source: "none",
                accessExpiresAt: nil,
                revokedAt: nil,
                fetchedAt: Date()
            )
        )
        defer {
            PersistedEntitlementSnapshotStore.clear(userID: freeProfile.rawValue)
            IosSubscriptionReleaseConfiguration.resetTestOverrides()
            DashboardAnalyticsAccountChartsStore.shared.invalidate()
        }

        DashboardAnalyticsAccountChartsStore.shared.invalidate()
        let revision: Int64 = 13
        let token = DashboardAnalyticsAccountChartsCoordinator.bumpSelection()
        let applied = await DashboardAnalyticsAccountChartsCoordinator.loadIfNeeded(
            selectedAccountID: liveAccount,
            selectionToken: token,
            revision: revision,
            viewerID: freeProfile,
            rpc: PremiumChartsRPCMustNotRun()
        )
        #expect(!applied)
        #expect(
            DashboardAnalyticsAccountChartsStore.shared.availability(accountID: liveAccount, revision: revision)
                == .failedNonRetryable
        )
    }
}