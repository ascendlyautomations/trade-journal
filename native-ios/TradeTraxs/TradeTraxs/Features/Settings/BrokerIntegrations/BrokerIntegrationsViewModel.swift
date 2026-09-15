import Foundation
import Observation

@Observable
@MainActor
final class BrokerIntegrationsViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var connections: [TradovateConnectionSummary] = []
    private(set) var accountsByConnection: [String: [BrokerIntegrationAccount]] = [:]
    private(set) var isConnecting = false
    private(set) var isDisconnecting = false
    private var activeConnectTask: Task<Void, Never>?

    var isBrokerConnectionMutationActive: Bool {
        isConnecting || isDisconnecting
    }
    private(set) var isRefreshingAccounts: Set<String> = []
    private(set) var importingMappingIds: Set<String> = []
    /// Link/import/disconnect feedback — not OAuth.
    private(set) var actionMessage: String?
    private(set) var actionIsError = false
    /// Recoverable Tradovate connect / sign-in URL errors — does not hide existing connections.
    private(set) var oauthErrorMessage: String?

    var pendingReviewTradeIDs: [TradeID] = []
    var showsReviewImportedTrades = false

    private let broker: any BrokerIntegrationRepository
    private let manageAccounts: ManageAccountsViewModel
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache

    init(
        broker: any BrokerIntegrationRepository,
        manageAccounts: ManageAccountsViewModel,
        session: any SessionProviding,
        detailCache: DetailPresentationCache
    ) {
        self.broker = broker
        self.manageAccounts = manageAccounts
        self.session = session
        self.detailCache = detailCache
    }

    func loadIfNeeded() {
        switch phase {
        case .idle, .failed:
            Task { await refreshAll() }
        case .loading, .loaded:
            break
        }
    }

    func refreshAll() async {
        let hadConnections = !connections.isEmpty
        if !hadConnections {
            phase = .loading
        }
        do {
            let response = try await broker.listTradovateConnections()
            connections = response.connections
            BrokerIntegrationDebugLog.uiConnections(count: connections.count)
            for connection in connections where connection.isActiveForBrokerUI {
                await loadAccounts(connectionId: connection.id, forceRefresh: false)
            }
            phase = .loaded
        } catch {
            let message = UserFacingError.message(for: error)
            if hadConnections {
                phase = .loaded
                presentMessage(message, error: true)
            } else {
                phase = .failed(message)
            }
        }
    }

    func connectTradovate(reconnectConnectionId: String? = nil) {
        guard !isBrokerConnectionMutationActive else { return }
        BrokerOAuthDebugLog.tap()
        activeConnectTask?.cancel()
        activeConnectTask = Task {
            isConnecting = true
            oauthErrorMessage = nil
            defer {
                isConnecting = false
                activeConnectTask = nil
            }
            do {
                let url = try await broker.beginTradovateNativeOAuth(reconnectConnectionId: reconnectConnectionId)
                let outcome = await TradovateBrokerOAuthSession.connect(authorizeURL: url)
                guard !Task.isCancelled else { return }
                switch outcome {
                case .success:
                    oauthErrorMessage = nil
                    await refreshAll()
                    presentMessage("Tradovate connected.", error: false)
                case .cancelled:
                    break
                case .error(let reason):
                    oauthErrorMessage = reason ?? "Tradovate connection failed."
                }
            } catch {
                if !Task.isCancelled {
                    oauthErrorMessage = UserFacingError.message(for: error)
                }
            }
        }
    }

    func disconnect(connectionId: String) async {
        guard !isBrokerConnectionMutationActive else { return }
        isDisconnecting = true
        defer { isDisconnecting = false }
        do {
            try await broker.disconnectTradovate(connectionId: connectionId)
            accountsByConnection[connectionId] = nil
            await refreshAll()
            presentMessage("Tradovate disconnected. Your trades and accounts were kept.", error: false)
        } catch {
            presentMessage(UserFacingError.message(for: error), error: true)
        }
    }

    func loadAccounts(connectionId: String, forceRefresh: Bool) async {
        isRefreshingAccounts.insert(connectionId)
        defer { isRefreshingAccounts.remove(connectionId) }
        do {
            let payload = try await broker.listTradovateAccounts(
                connectionId: connectionId,
                forceRefresh: forceRefresh
            )
            accountsByConnection[connectionId] = payload.accounts
        } catch {
            presentMessage(UserFacingError.message(for: error), error: true)
        }
    }

    func accounts(for connectionId: String) -> [BrokerIntegrationAccount] {
        accountsByConnection[connectionId] ?? []
    }

    func linkExisting(
        connectionId: String,
        brokerAccount: BrokerIntegrationAccount,
        tradetraxsAccountId: TradingAccountID
    ) async -> Bool {
        do {
            let response = try await broker.linkTradovateAccount(
                connectionId: connectionId,
                brokerIntegrationAccountId: brokerAccount.id,
                tradetraxsAccountId: tradetraxsAccountId.rawValue
            )
            accountsByConnection[connectionId] = response.accounts
            await refreshCanonicalAccounts()
            presentMessage("Account linked.", error: false)
            return true
        } catch {
            presentMessage(UserFacingError.message(for: error), error: true)
            return false
        }
    }

    func createAndLink(
        connectionId: String,
        brokerAccount: BrokerIntegrationAccount,
        draft: TradingAccountDraft
    ) async -> Bool {
        do {
            let response = try await broker.createAndLinkTradovateAccount(
                connectionId: connectionId,
                brokerIntegrationAccountId: brokerAccount.id,
                draft: draft
            )
            accountsByConnection[connectionId] = response.accounts
            await refreshCanonicalAccounts()
            presentMessage("Trading account created and linked.", error: false)
            return true
        } catch {
            presentMessage(UserFacingError.message(for: error), error: true)
            return false
        }
    }

    func importTrades(connectionId: String, mappingId: String) async {
        importingMappingIds.insert(mappingId)
        defer { importingMappingIds.remove(mappingId) }
        do {
            let response = try await broker.syncTradovateAccount(
                connectionId: connectionId,
                mappingId: mappingId
            )
            accountsByConnection[connectionId] = response.accounts
            let newIds = response.summary.newTradeIds
            await refreshTradesAfterImport(newTradeIds: newIds)
            if response.summary.ok {
                if newIds.isEmpty {
                    presentMessage("Import finished — no new trades.", error: false)
                } else {
                    pendingReviewTradeIDs = newIds.map { TradeID($0) }
                    showsReviewImportedTrades = true
                    presentMessage("Imported \(newIds.count) trade(s).", error: false)
                }
            } else {
                presentMessage(response.summary.error ?? "Import did not complete.", error: true)
            }
        } catch {
            presentMessage(UserFacingError.message(for: error), error: true)
        }
    }

    func handleOAuthDeepLink(status: String?, reason: String?) async {
        if status == "success" {
            oauthErrorMessage = nil
            await refreshAll()
            presentMessage("Tradovate connected.", error: false)
        } else if status == "error" {
            oauthErrorMessage = reason ?? "Tradovate connection failed."
        }
    }

    func draftForCreate(from account: BrokerIntegrationAccount) -> TradingAccountDraft {
        BrokerIntegrationAccountDraftEncoding.draft(
            externalAccountId: account.externalAccountId,
            externalAccountName: account.externalAccountName,
            metadata: account.metadata
        )
    }

    // MARK: - Private

    private func refreshCanonicalAccounts() async {
        await manageAccounts.refresh()
        if let userID = await session.currentUserID {
            let viewerID = ProfileID(userID.rawValue)
            AccountMutationStore.shared.noteAccountsChanged(
                allAccounts: manageAccounts.accounts,
                viewerID: viewerID
            )
        }
    }

    private func refreshTradesAfterImport(newTradeIds: [String]) async {
        guard let userID = await session.currentUserID else { return }
        let owner = ProfileID(userID.rawValue)
        TradeJournalMutationStore.shared.noteBulkImport(owner: owner)
        _ = newTradeIds
    }

    private func presentMessage(_ message: String, error: Bool) {
        actionMessage = message
        actionIsError = error
    }
}
