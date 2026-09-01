import Foundation
import Observation

@Observable
@MainActor
final class PropFirmDetailViewModel {
    let accountID: TradingAccountID
    private(set) var snapshot: PropFirmStatusSnapshot?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let trades: any TradeRepository
    private let rpc: (any RPCClient)?
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let realtimeHub: RealtimeHub?

    private var hasLoaded = false
    private var watchedChannel: RealtimeChannelID?
    private var realtimeTask: Task<Void, Never>?

    init(
        accountID: TradingAccountID,
        trades: any TradeRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        rpc: (any RPCClient)? = nil,
        realtimeHub: RealtimeHub? = nil
    ) {
        self.accountID = accountID
        self.trades = trades
        self.rpc = rpc
        self.session = session
        self.detailCache = detailCache
        self.realtimeHub = realtimeHub
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await refresh()
    }

    func refresh() async {
        isLoading = snapshot == nil
        errorMessage = nil
        let userID = await session.currentUserID
        let profileID = ProfileID(userID?.rawValue ?? "dev.screenshot")

        do {
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
                    await startRealtime(profileID: profileID)
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
                    // Fall through to legacy REST path.
                }
            }

            let accounts: [TradingAccount]
            if ProfileSectionSupport.isLocalDevelopmentProfile(profileID) {
                accounts = PropFirmFixtures.accounts(owner: profileID)
                SessionAccountsStore.shared.seed(accounts, for: profileID, detailCache: detailCache)
            } else {
                accounts = try await SessionAccountsStore.shared.accounts(
                    for: profileID,
                    detailCache: detailCache,
                    repository: trades
                )
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

            snapshot = PropFirmStatusSnapshot.build(account: account, trades: tradeList)
            hasLoaded = true
            await startRealtime(profileID: profileID)
        } catch {
            errorMessage = ProfileSectionSupport.message(for: error)
        }
        isLoading = false
    }

    func onDisappear() {
        Task { await stopRealtime() }
    }

    private func startRealtime(profileID: ProfileID) async {
        guard let realtimeHub else { return }
        await stopRealtime()
        let channel = RealtimeChannelID(
            kind: .profile,
            topic: "propfirm:\(accountID.rawValue)"
        )
        watchedChannel = channel
        try? await realtimeHub.subscriptions.subscribe(channel)
        realtimeTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
    }

    private func stopRealtime() async {
        realtimeTask?.cancel()
        realtimeTask = nil
        guard let realtimeHub, let channel = watchedChannel else { return }
        try? await realtimeHub.subscriptions.unsubscribe(channel)
        watchedChannel = nil
    }
}
