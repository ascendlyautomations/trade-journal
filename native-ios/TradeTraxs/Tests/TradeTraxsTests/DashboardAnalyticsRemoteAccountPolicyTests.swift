import Foundation
import Testing
@testable import TradeTraxs

private struct ChartRPCMustNotRun: RPCClient {
    func call(functionName: String, parameters: [String: String]) async throws -> Data {
        Issue.record("RPC must not run for ineligible account charts")
        throw AppError.unknown(message: "unexpected rpc")
    }

    func call(functionName: String, jsonBody: Data) async throws -> Data {
        Issue.record("RPC must not run for ineligible account charts")
        throw AppError.unknown(message: "unexpected rpc")
    }
}

@MainActor
struct DashboardAnalyticsRemoteAccountPolicyTests {
    private let liveProfile = ProfileID("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
    private let liveAccount = TradingAccountID("11111111-1111-4111-8111-111111111111")

    @Test("Bundled demo account IDs never use production chart RPCs")
    func canonicalAccountBlockedForSignedInProfile() {
        let demo = DemoCanonicalDataset.evaluationAccountID
        #expect(JournalSampleDataPolicy.isCanonicalAccount(id: demo))
        #expect(
            DashboardAnalyticsRemoteAccountPolicy.shouldFetchAccountChartsRemotely(
                accountID: demo,
                profileID: liveProfile
            ) == false
        )
    }

    @Test("Live authenticated accounts remain chart-RPC eligible")
    func liveUUIDRemainsEligible() {
        #expect(
            DashboardAnalyticsRemoteAccountPolicy.shouldFetchAccountChartsRemotely(
                accountID: liveAccount,
                profileID: liveProfile
            )
        )
    }

    @Test("Explore bundled journal profile skips remote chart RPCs")
    func exploreProfileSkipsRemoteCharts() {
        #expect(JournalSampleDataPolicy.usesCanonicalJournalData(for: DemoExperienceSupport.profileID))
        #expect(
            DashboardAnalyticsRemoteAccountPolicy.shouldFetchAccountChartsRemotely(
                accountID: liveAccount,
                profileID: DemoExperienceSupport.profileID
            ) == false
        )
    }

    @Test("Persistence maps stale demo account selection to all accounts")
    func persistenceStripsDemoAccountKey() {
        let key = DemoCanonicalDataset.evaluationAccountID.rawValue
        #expect(DashboardScopeFilterPersistence.accountFilter(from: key) == .all)
        #expect(
            DashboardScopeFilterPersistence.accountFilterKey(
                for: .account(DemoCanonicalDataset.evaluationAccountID)
            ) == "all"
        )
    }

    @Test("Unknown account filter sanitizes to all when account list changes")
    func sanitizedFilterDropsMissingAccount() {
        let owner = ProfileID("scope.owner")
        let live = TradingAccount(
            id: liveAccount,
            ownerProfileID: owner,
            name: "Live",
            category: .personal,
            mode: .live,
            size: nil,
            isActive: true,
            canAddTrades: true,
            accountNumber: nil
        )
        let sanitized = DashboardAccountScopePolicy.sanitizedFilter(
            .account(DemoCanonicalDataset.evaluationAccountID),
            accounts: [live]
        )
        #expect(sanitized == .all)
    }

    @Test("22P02 invalid UUID errors are non-retryable")
    func invalidUUIDPostgreSQLCodeDoesNotRetry() {
        let error = NSError(
            domain: "PostgREST",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "22P02: invalid input syntax for type uuid"]
        )
        #expect(DashboardAnalyticsChartsFailurePolicy.shouldNotRetry(error))
    }

    @Test("Rapid account switch does not call RPC for demo account")
    func rapidSwitchSkipsDemoAccountRPC() async {
        DashboardAnalyticsAccountChartsStore.shared.invalidate()
        let revision: Int64 = 11
        let realAccount = liveAccount
        let demo = DemoCanonicalDataset.evaluationAccountID

        let tokenA = DashboardAnalyticsAccountChartsCoordinator.bumpSelection()
        _ = await DashboardAnalyticsAccountChartsCoordinator.loadIfNeeded(
            selectedAccountID: realAccount,
            selectionToken: tokenA,
            revision: revision,
            viewerID: liveProfile,
            rpc: ChartRPCMustNotRun()
        )

        let tokenB = DashboardAnalyticsAccountChartsCoordinator.bumpSelection()
        let applied = await DashboardAnalyticsAccountChartsCoordinator.loadIfNeeded(
            selectedAccountID: demo,
            selectionToken: tokenB,
            revision: revision,
            viewerID: liveProfile,
            rpc: ChartRPCMustNotRun()
        )

        #expect(applied == false)
        #expect(tokenB == DashboardAnalyticsAccountChartsCoordinator.currentSelectionToken())
        #expect(
            DashboardAnalyticsAccountChartsStore.shared.availability(
                accountID: demo,
                revision: revision
            ) == .failedNonRetryable
        )
    }

    @Test("Loader rejects ineligible accounts before coalesced fetch")
    func loaderThrowsBeforeRPC() async {
        DashboardAnalyticsAccountChartsStore.shared.invalidate()
        let demo = DemoCanonicalDataset.evaluationAccountID
        do {
            _ = try await DashboardAnalyticsAccountChartsLoader.loadCoalesced(
                accountID: demo,
                revision: 1,
                rpc: ChartRPCMustNotRun(),
                viewerID: liveProfile
            )
            Issue.record("Expected remoteAccountIneligible")
        } catch let error as DashboardAnalyticsAccountChartsLoaderError {
            #expect(error == .remoteAccountIneligible)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}