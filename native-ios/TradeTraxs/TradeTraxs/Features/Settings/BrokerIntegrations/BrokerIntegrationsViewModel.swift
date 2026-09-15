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
    private(set) var tradovateConnections: [TradovateConnectionSummary] = []
    private(set) var rithmicConnections: [TradovateConnectionSummary] = []
    private(set) var rithmicConnectCapabilities: RithmicConnectCapabilitiesResponse?
    private(set) var accountsByConnection: [String: [BrokerIntegrationAccount]] = [:]
    private(set) var isConnecting = false
    private(set) var isConnectingRithmic = false
    private(set) var isDisconnecting = false
    private var activeConnectTask: Task<Void, Never>?

    var showsRithmicConnectSheet = false
    private(set) var rithmicSystemChoices: [String] = []
    var rithmicReconnectConnectionId: String?

    var isBrokerConnectionMutationActive: Bool {
        isConnecting || isConnectingRithmic || isDisconnecting
    }
    private(set) var isRefreshingAccounts: Set<String> = []
    private(set) var importingMappingIds: Set<String> = []
    private(set) var actionMessage: String?
    private(set) var actionIsError = false
    private(set) var oauthErrorMessage: String?

    var pendingReviewTradeIDs: [TradeID] = []
    var showsReviewImportedTrades = false

    var isRithmicConnectUIAvailable: Bool {
        rithmicConnectCapabilities?.showConnectUi == true
    }

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
        let hadConnections = !tradovateConnections.isEmpty || !rithmicConnections.isEmpty
        if !hadConnections {
            phase = .loading
        }
        var loadError: String?

        do {
            let response = try await broker.listTradovateConnections()
            tradovateConnections = response.connections
            BrokerIntegrationDebugLog.uiConnections(count: tradovateConnections.count)
            for connection in tradovateConnections where connection.isActiveForBrokerUI {
                await loadAccounts(provider: .tradovate, connectionId: connection.id, forceRefresh: false)
            }
        } catch {
            loadError = UserFacingError.message(for: error)
        }

        do {
            let response = try await broker.listRithmicConnections()
            rithmicConnections = response.connections
            for connection in rithmicConnections where connection.isActiveForBrokerUI {
                await loadAccounts(provider: .rithmic, connectionId: connection.id, forceRefresh: false)
            }
        } catch {
            if loadError == nil {
                loadError = UserFacingError.message(for: error)
            }
        }

        do {
            rithmicConnectCapabilities = try await broker.fetchRithmicConnectCapabilities()
        } catch {
            rithmicConnectCapabilities = nil
        }

        if tradovateConnections.isEmpty, rithmicConnections.isEmpty, let loadError {
            phase = .failed(loadError)
        } else {
            phase = .loaded
            if let loadError {
                presentMessage(loadError, error: true)
            }
        }
        BrokerImportEligibilityStore.shared.refresh()
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

    func presentRithmicConnect(reconnectConnectionId: String? = nil) {
        guard isRithmicConnectUIAvailable, !isBrokerConnectionMutationActive else { return }
        rithmicReconnectConnectionId = reconnectConnectionId
        if reconnectConnectionId == nil {
            rithmicSystemChoices = []
        }
        showsRithmicConnectSheet = true
    }

    func submitRithmicConnect(username: String, password: String, systemName: String?) async {
        guard !isBrokerConnectionMutationActive else { return }
        isConnectingRithmic = true
        defer { isConnectingRithmic = false }
        do {
            let outcome = try await broker.connectRithmic(
                username: username,
                password: password,
                systemName: systemName,
                reconnectConnectionId: rithmicReconnectConnectionId
            )
            switch outcome {
            case .systemSelectionRequired(let names, let message):
                rithmicSystemChoices = names
                presentMessage(message, error: false)
            case .connected:
                rithmicSystemChoices = []
                rithmicReconnectConnectionId = nil
                showsRithmicConnectSheet = false
                await refreshAll()
                presentMessage("Rithmic connected.", error: false)
            }
        } catch {
            presentMessage(UserFacingError.message(for: error), error: true)
        }
    }

    func disconnect(provider: BrokerIntegrationProvider, connectionId: String) async {
        guard !isBrokerConnectionMutationActive else { return }
        isDisconnecting = true
        defer { isDisconnecting = false }
        do {
            switch provider {
            case .tradovate:
                try await broker.disconnectTradovate(connectionId: connectionId)
            case .rithmic:
                try await broker.disconnectRithmic(connectionId: connectionId)
            }
            accountsByConnection[connectionId] = nil
            await refreshAll()
            let label = provider == .tradovate ? "Tradovate" : "Rithmic"
            presentMessage("\(label) disconnected. Your trades and accounts were kept.", error: false)
        } catch {
            presentMessage(UserFacingError.message(for: error), error: true)
        }
    }

    func loadAccounts(provider: BrokerIntegrationProvider, connectionId: String, forceRefresh: Bool) async {
        isRefreshingAccounts.insert(connectionId)
        defer { isRefreshingAccounts.remove(connectionId) }
        do {
            let payload: TradovateConnectionAccountsResponse
            switch provider {
            case .tradovate:
                payload = try await broker.listTradovateAccounts(connectionId: connectionId, forceRefresh: forceRefresh)
            case .rithmic:
                payload = try await broker.listRithmicAccounts(connectionId: connectionId)
            }
            accountsByConnection[connectionId] = payload.accounts
        } catch {
            presentMessage(UserFacingError.message(for: error), error: true)
        }
    }

    func accounts(for connectionId: String) -> [BrokerIntegrationAccount] {
        accountsByConnection[connectionId] ?? []
    }

    func linkExisting(
        provider: BrokerIntegrationProvider,
        connectionId: String,
        brokerAccount: BrokerIntegrationAccount,
        tradetraxsAccountId: TradingAccountID
    ) async -> Bool {
        do {
            let response: BrokerLinkAccountsResponse
            switch provider {
            case .tradovate:
                response = try await broker.linkTradovateAccount(
                    connectionId: connectionId,
                    brokerIntegrationAccountId: brokerAccount.id,
                    tradetraxsAccountId: tradetraxsAccountId.rawValue
                )
            case .rithmic:
                response = try await broker.linkRithmicAccount(
                    connectionId: connectionId,
                    brokerIntegrationAccountId: brokerAccount.id,
                    tradetraxsAccountId: tradetraxsAccountId.rawValue
                )
            }
            accountsByConnection[connectionId] = response.accounts
            await refreshCanonicalAccounts()
            BrokerImportEligibilityStore.shared.refresh(fromUserAction: false)
            presentMessage("Account linked.", error: false)
            return true
        } catch {
            presentMessage(UserFacingError.message(for: error), error: true)
            return false
        }
    }

    func createAndLink(
        provider: BrokerIntegrationProvider,
        connectionId: String,
        brokerAccount: BrokerIntegrationAccount,
        draft: TradingAccountDraft
    ) async -> Bool {
        do {
            let response: BrokerLinkAccountsResponse
            switch provider {
            case .tradovate:
                response = try await broker.createAndLinkTradovateAccount(
                    connectionId: connectionId,
                    brokerIntegrationAccountId: brokerAccount.id,
                    draft: draft
                )
            case .rithmic:
                response = try await broker.createAndLinkRithmicAccount(
                    connectionId: connectionId,
                    brokerIntegrationAccountId: brokerAccount.id,
                    draft: draft
                )
            }
            accountsByConnection[connectionId] = response.accounts
            await refreshCanonicalAccounts()
            BrokerImportEligibilityStore.shared.refresh(fromUserAction: false)
            presentMessage("Trading account created and linked.", error: false)
            return true
        } catch {
            presentMessage(UserFacingError.message(for: error), error: true)
            return false
        }
    }

    func importTrades(provider: BrokerIntegrationProvider, connectionId: String, mappingId: String) async {
        importingMappingIds.insert(mappingId)
        defer { importingMappingIds.remove(mappingId) }
        do {
            let response: TradovateAccountSyncResponse
            switch provider {
            case .tradovate:
                response = try await broker.syncTradovateAccount(connectionId: connectionId, mappingId: mappingId)
            case .rithmic:
                response = try await broker.syncRithmicAccount(connectionId: connectionId, mappingId: mappingId)
            }
            accountsByConnection[connectionId] = response.accounts
            let newIds = response.summary.newTradeIds
            await refreshTradesAfterImport(newTradeIds: newIds)
            if response.summary.ok {
                presentMessage(BrokerIntegrationDisplay.importResultMessage(newTradeCount: newIds.count), error: false)
                if !newIds.isEmpty {
                    pendingReviewTradeIDs = newIds.map { TradeID($0) }
                    showsReviewImportedTrades = true
                }
            } else {
                presentMessage(
                    BrokerIntegrationDisplay.importFailureMessage(serverSummary: response.summary.error),
                    error: true
                )
            }
        } catch {
            presentMessage(BrokerIntegrationDisplay.importFailureMessage(for: error), error: true)
        }
    }

    func isImportingTrades(mappingId: String) -> Bool {
        importingMappingIds.contains(mappingId)
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
        switch account.provider {
        case .rithmic:
            return BrokerIntegrationAccountDraftEncoding.rithmicDraft(
                externalAccountId: account.externalAccountId,
                externalAccountName: account.externalAccountName,
                externalDisplayName: account.externalDisplayName,
                metadata: account.metadata
            )
        case .tradovate:
            return BrokerIntegrationAccountDraftEncoding.draft(
                externalAccountId: account.externalAccountId,
                externalAccountName: account.externalAccountName,
                metadata: account.metadata
            )
        }
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
