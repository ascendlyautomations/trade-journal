import Foundation
import Observation

@Observable
@MainActor
final class PropFirmDetailViewModel {
    private(set) var accountID: TradingAccountID
    private(set) var snapshot: PropFirmStatusSnapshot?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var propFirmAccounts: [TradingAccount] = []
    private(set) var ownerProfileID: ProfileID?

    private let trades: any TradeRepository
    private let rpc: (any RPCClient)?
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let realtimeHub: RealtimeHub?
    private let navigationCoordinator: NavigationCoordinator?

    private var hasLoaded = false

    init(
        accountID: TradingAccountID,
        trades: any TradeRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        rpc: (any RPCClient)? = nil,
        realtimeHub: RealtimeHub? = nil,
        navigationCoordinator: NavigationCoordinator? = nil
    ) {
        self.accountID = accountID
        self.trades = trades
        self.rpc = rpc
        self.session = session
        self.detailCache = detailCache
        self.realtimeHub = realtimeHub
        self.navigationCoordinator = navigationCoordinator
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await refresh()
    }

    var accountsForMenu: [TradingAccount] {
        let selected = accountID
        return OwnerAccountDropdownSupport.menuAccounts(
            profileID: ownerProfileID,
            fallback: propFirmAccounts,
            preservingSelection: selected
        ).filter(\.isPropFirmAccount)
    }

    func accountMenuTitle(for account: TradingAccount) -> String {
        TradingAccountDisplay.ownerDropdownLine(for: account)
    }

    var selectedAccountMenuTitle: String {
        if let account = propFirmAccounts.first(where: { $0.id == accountID }) {
            return accountMenuTitle(for: account)
        }
        return snapshot?.accountName ?? "Prop account"
    }

    func selectAccount(_ id: TradingAccountID) async {
        guard id != accountID else { return }
        guard propFirmAccounts.contains(where: { $0.id == id && $0.isPropFirmAccount }) else { return }
        accountID = id
        await refresh()
    }

    func openManageAccounts() {
        navigationCoordinator?.open(.settingsStack([.home, .tradingAccounts]))
    }

    func handleAccountMutation() {
        guard let ownerProfileID else { return }
        guard let loaded = OwnerAccountMutationSync.sessionAccounts(
            profileID: ownerProfileID,
            detailCache: detailCache
        ) else { return }
        propFirmAccounts = loaded.filter(\.isPropFirmAccount)
        OwnerAccountMutationSync.seedDetailCacheIfNeeded(loaded, profileID: ownerProfileID, detailCache: detailCache)
    }

    func openPayoutsPage() {
        navigationCoordinator?.pushHome(.propFirmPayouts(accountID))
    }

    static func payoutEntryTitle(hasRecordedPayouts: Bool) -> String {
        hasRecordedPayouts ? "Payouts" : "Record Payout"
    }

    func refresh() async {
        isLoading = snapshot == nil
        errorMessage = nil
        let userID = await session.currentUserID
        let demoActive = AppLaunchController.shared.isDemoExperienceActive
        guard case .viewer(let profileID) = SessionViewerIdentity.resolve(
            userID: userID,
            demoExperienceActive: demoActive
        ) else {
            if snapshot == nil {
                errorMessage = SessionViewerIdentity.sessionUnavailableMessage
            }
            isLoading = false
            return
        }

        do {
            if ProfileSectionSupport.isLocalDevelopmentProfile(profileID) {
                let latestUserID = await session.currentUserID
                guard SessionViewerIdentity.shouldCommit(
                    resolved: profileID,
                    userID: latestUserID,
                    demoExperienceActive: AppLaunchController.shared.isDemoExperienceActive
                ) else {
                    if let latestUserID, ProfileID(latestUserID.rawValue) != profileID {
                        await refresh()
                    } else if snapshot == nil {
                        errorMessage = SessionViewerIdentity.sessionUnavailableMessage
                    }
                    isLoading = false
                    return
                }
            }

            ownerProfileID = profileID
            let accounts = try await loadTradingAccounts(profileID: profileID)
            propFirmAccounts = accounts.filter(\.isPropFirmAccount)

            if let rpc, !ProfileSectionSupport.isLocalDevelopmentProfile(profileID) {
                do {
                    let result = try await PropFirmBootstrapLoader.load(
                        accountID: accountID,
                        profileID: profileID,
                        rpc: rpc,
                        detailCache: detailCache
                    )
                    snapshot = result.snapshot
                    hasLoaded = true
                    isLoading = false
                    return
                } catch PropFirmBootstrapLoader.LoaderError.flagOff,
                        PropFirmBootstrapLoader.LoaderError.rpcUnavailable {
                    // Fall through to legacy REST path.
                } catch PropFirmBootstrapLoader.LoaderError.accountNotFound {
                    snapshot = nil
                    errorMessage = "This account is not a prop-firm account."
                    isLoading = false
                    return
                } catch {
                    if ProLimitPresentation.presentUpgradeIfProGate(error) {
                        isLoading = false
                        return
                    }
                    // Fall through to legacy REST path.
                }
            }

            guard let account = accounts.first(where: { $0.id == accountID }),
                  account.isPropFirmAccount
            else {
                snapshot = nil
                errorMessage = "This account is not a prop-firm account."
                isLoading = false
                return
            }

            let tradeList: [Trade]
            if ProfileSectionSupport.isLocalDevelopmentProfile(profileID) {
                tradeList = PropFirmFixtures.trades(owner: profileID, accountID: accountID)
            } else if let cached = detailCache.publicTrades(for: profileID) {
                // Prefer seeded dashboard trades when present; else fetch.
                let scoped = cached.filter { $0.accountID == accountID }
                if scoped.isEmpty {
                    let page = try await trades.trades(
                        ownedBy: profileID,
                        accountID: accountID,
                        page: PageRequest(limit: 500),
                        publicOnly: false
                    )
                    tradeList = page.items
                    detailCache.seed(trades: page.items)
                } else {
                    tradeList = scoped
                }
            } else {
                let page = try await trades.trades(
                    ownedBy: profileID,
                    accountID: accountID,
                    page: PageRequest(limit: 500),
                    publicOnly: false
                )
                tradeList = page.items
                detailCache.seed(trades: page.items)
            }

            let payoutCycles: [AccountPayoutCycle]
            if ProfileSectionSupport.isLocalDevelopmentProfile(profileID) {
                payoutCycles = []
            } else {
                payoutCycles = try await trades.payoutCycleHistory(for: accountID)
            }

            snapshot = PropFirmStatusSnapshot.build(
                account: account,
                trades: tradeList,
                payoutCycles: payoutCycles
            )
            hasLoaded = true
        } catch {
            errorMessage = ProfileSectionSupport.message(for: error)
        }
        isLoading = false
    }

    func onDisappear() {}

    private func loadTradingAccounts(profileID: ProfileID) async throws -> [TradingAccount] {
        if ProfileSectionSupport.isLocalDevelopmentProfile(profileID) {
            let accounts = PropFirmFixtures.accounts(owner: profileID)
            SessionAccountsStore.shared.seed(accounts, for: profileID, detailCache: detailCache)
            return accounts
        }
        return try await SessionAccountsStore.shared.accounts(
            for: profileID,
            detailCache: detailCache,
            repository: trades
        )
    }
}
