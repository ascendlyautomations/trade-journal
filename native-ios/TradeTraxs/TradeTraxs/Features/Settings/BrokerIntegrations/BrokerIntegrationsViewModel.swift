import Foundation
import Observation

@Observable
@MainActor
final class BrokerIntegrationsViewModel {
    enum Phase: Equatable {
        case idle
        case loaded
    }

    enum BrokerProviderLoadPhase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var tradovateLoadPhase: BrokerProviderLoadPhase = .idle
    private(set) var rithmicConnectionsLoadPhase: BrokerProviderLoadPhase = .idle
    private var refreshTask: Task<Void, Never>?
    private(set) var tradovateConnections: [TradovateConnectionSummary] = []
    private(set) var rithmicConnections: [TradovateConnectionSummary] = []
    enum RithmicConnectCapabilitiesPhase: Equatable {
        case loading
        case loaded
        case failed
    }

    private(set) var rithmicConnectCapabilities: RithmicConnectCapabilitiesResponse?
    private(set) var rithmicConnectCapabilitiesPhase: RithmicConnectCapabilitiesPhase = .loading
    private(set) var accountsByConnection: [String: [BrokerIntegrationAccount]] = [:]
    private(set) var isConnecting = false
    private(set) var isConnectingRithmic = false
    private(set) var isDisconnecting = false
    private var activeConnectTask: Task<Void, Never>?

    var showsRithmicConnectSheet = false
    private(set) var rithmicSystemChoices: [String] = []
    var rithmicReconnectConnectionId: String?
    private(set) var rithmicImportReauthConnectionId: String?
    private(set) var rithmicImportReauthMappingId: String?

    var rithmicConnectSheetMode: RithmicConnectSheetMode {
        rithmicImportReauthMappingId == nil ? .connect : .importTrades
    }

    var rithmicSheetPrefilledUsername: String? {
        if let connectionId = rithmicImportReauthConnectionId ?? rithmicReconnectConnectionId {
            return rithmicConnections.first(where: { $0.id == connectionId })?.brokerLoginUsername
        }
        return nil
    }

    var rithmicSheetPrefilledSystemName: String? {
        if let connectionId = rithmicImportReauthConnectionId ?? rithmicReconnectConnectionId {
            return rithmicConnections.first(where: { $0.id == connectionId })?.providerDisplayName
        }
        return nil
    }

    var rithmicSheetLocksUsername: Bool {
        rithmicImportReauthMappingId != nil
            || (rithmicReconnectConnectionId != nil && rithmicSheetPrefilledUsername != nil)
    }

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
        rithmicConnectCapabilitiesPhase == .loaded
            && rithmicConnectCapabilities?.showConnectUi == true
    }

    /// Broker onboarding lists Rithmic while availability is still resolving (settings always shows the provider).
    var showsRithmicBrokerOnboardingOption: Bool {
        if !rithmicConnections.isEmpty { return true }
        switch rithmicConnectCapabilitiesPhase {
        case .loading:
            return true
        case .loaded:
            return rithmicConnectCapabilities?.showConnectUi == true
        case .failed:
            return false
        }
    }

    var hasActiveConnectedBroker: Bool {
        activeConnectedConnections().isEmpty == false
    }

    var unlinkedBrokerAccountsCount: Int {
        activeConnectedConnections().reduce(into: 0) { partial, connection in
            partial += accounts(for: connection.id).filter { !$0.hasTradetraxsMapping }.count
        }
    }

    /// Connected broker with every discovered account linked (or none discovered yet).
    var brokerOnboardingReadyToContinue: Bool {
        guard hasActiveConnectedBroker else { return false }
        return unlinkedBrokerAccountsCount == 0
    }

    func firstUnlinkedBrokerAccount() -> (provider: BrokerIntegrationProvider, connectionId: String, account: BrokerIntegrationAccount)? {
        for connection in tradovateConnections.filter({ $0.isActiveForBrokerUI && $0.connected }) {
            if let account = accounts(for: connection.id).first(where: { !$0.hasTradetraxsMapping }) {
                return (.tradovate, connection.id, account)
            }
        }
        for connection in rithmicConnections.filter({ $0.isActiveForBrokerUI && $0.connected }) {
            if let account = accounts(for: connection.id).first(where: { !$0.hasTradetraxsMapping }) {
                return (.rithmic, connection.id, account)
            }
        }
        return nil
    }

    private func activeConnectedConnections() -> [TradovateConnectionSummary] {
        (tradovateConnections + rithmicConnections).filter { $0.isActiveForBrokerUI && $0.connected }
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
        guard phase == .idle else { return }
        Task { await refreshAll() }
    }

    func refreshAll() async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        let task = Task { await performRefreshAll() }
        refreshTask = task
        defer { refreshTask = nil }
        await task.value
    }

    private func performRefreshAll() async {
        phase = .loaded

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshTradovateConnections() }
            group.addTask { await self.refreshRithmicConnections() }
            group.addTask { await self.refreshRithmicCapabilities() }
        }

        noteBrokerIntegrationChanged()
    }

    private func refreshTradovateConnections() async {
        if tradovateConnections.isEmpty {
            tradovateLoadPhase = .loading
        }
        do {
            let response = try await broker.listTradovateConnections()
            tradovateConnections = response.connections
            BrokerIntegrationDebugLog.uiConnections(count: tradovateConnections.count)
            let active = tradovateConnections.filter(\.isActiveForBrokerUI).count
            BrokerIntegrationDebugLog.uiActiveConnections(count: active, connected: tradovateConnections.filter(\.connected).count)
            tradovateLoadPhase = .loaded
            await loadAccountsInParallel(
                provider: .tradovate,
                connections: tradovateConnections.filter(\.isActiveForBrokerUI),
                forceRefresh: false
            )
        } catch {
            let category = TradovateConnectionDiagnostics.safeFailureCategory(for: error)
            BrokerIntegrationDebugLog.tradovateLoadFailed(category: category)
            let message = UserFacingError.message(for: error)
            if tradovateConnections.isEmpty {
                tradovateLoadPhase = .failed(message)
            } else {
                tradovateLoadPhase = .loaded
                presentMessage(message, error: true)
            }
        }
    }

    private func refreshRithmicConnections() async {
        if rithmicConnections.isEmpty {
            rithmicConnectionsLoadPhase = .loading
        }
        do {
            let response = try await broker.listRithmicConnections()
            rithmicConnections = response.connections
            rithmicConnectionsLoadPhase = .loaded
            await loadAccountsInParallel(
                provider: .rithmic,
                connections: rithmicConnections.filter(\.isActiveForBrokerUI),
                forceRefresh: false
            )
        } catch {
            let message = UserFacingError.message(for: error)
            if rithmicConnections.isEmpty {
                rithmicConnectionsLoadPhase = .failed(message)
            } else {
                rithmicConnectionsLoadPhase = .loaded
                presentMessage(message, error: true)
            }
        }
    }

    private func refreshRithmicCapabilities() async {
        if rithmicConnectCapabilitiesPhase != .loaded {
            rithmicConnectCapabilitiesPhase = .loading
        }
        do {
            rithmicConnectCapabilities = try await broker.fetchRithmicConnectCapabilities()
            rithmicConnectCapabilitiesPhase = .loaded
        } catch {
            rithmicConnectCapabilities = nil
            rithmicConnectCapabilitiesPhase = .failed
        }
    }

    private func loadAccountsInParallel(
        provider: BrokerIntegrationProvider,
        connections: [TradovateConnectionSummary],
        forceRefresh: Bool
    ) async {
        await withTaskGroup(of: Void.self) { group in
            for connection in connections {
                group.addTask {
                    await self.loadAccounts(
                        provider: provider,
                        connectionId: connection.id,
                        forceRefresh: forceRefresh
                    )
                }
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

    func presentRithmicConnect(reconnectConnectionId: String? = nil) {
        guard isRithmicConnectUIAvailable, !isBrokerConnectionMutationActive else { return }
        rithmicImportReauthConnectionId = nil
        rithmicImportReauthMappingId = nil
        rithmicReconnectConnectionId = reconnectConnectionId
        if reconnectConnectionId == nil {
            rithmicSystemChoices = []
        }
        showsRithmicConnectSheet = true
    }

    func presentRithmicImportReauth(connectionId: String, mappingId: String) {
        guard !isBrokerConnectionMutationActive else { return }
        rithmicImportReauthConnectionId = connectionId
        rithmicImportReauthMappingId = mappingId
        rithmicReconnectConnectionId = nil
        rithmicSystemChoices = []
        showsRithmicConnectSheet = true
    }

    func submitRithmicConnect(username: String, password: String, systemName: String?) async {
        guard !isBrokerConnectionMutationActive else { return }
        if let connectionId = rithmicImportReauthConnectionId,
           let mappingId = rithmicImportReauthMappingId
        {
            await submitRithmicImportReauth(
                connectionId: connectionId,
                mappingId: mappingId,
                password: password
            )
            return
        }
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

    private func submitRithmicImportReauth(
        connectionId: String,
        mappingId: String,
        password: String
    ) async {
        isConnectingRithmic = true
        defer { isConnectingRithmic = false }
        do {
            let response = try await broker.syncRithmicAccount(
                connectionId: connectionId,
                mappingId: mappingId,
                password: password
            )
            accountsByConnection[connectionId] = response.accounts
            let newIds = response.summary.newTradeIds
            await refreshTradesAfterImport(newTradeIds: newIds)
            if response.summary.ok {
                rithmicImportReauthConnectionId = nil
                rithmicImportReauthMappingId = nil
                showsRithmicConnectSheet = false
                noteBrokerIntegrationChanged()
                presentMessage(BrokerIntegrationDisplay.importResultMessage(newTradeCount: newIds.count), error: false)
                if !newIds.isEmpty {
                    pendingReviewTradeIDs = newIds.map { TradeID($0) }
                    showsReviewImportedTrades = true
                }
            } else if response.summary.errorCode == "rithmic_password_required" {
                presentMessage(
                    response.summary.error ?? "Enter your Rithmic password to import.",
                    error: true
                )
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

    func clearRithmicSheetStateOnDismiss() {
        rithmicImportReauthConnectionId = nil
        rithmicImportReauthMappingId = nil
        rithmicReconnectConnectionId = nil
        rithmicSystemChoices = []
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
            noteBrokerIntegrationChanged()
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
            noteBrokerIntegrationChanged()
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
                response = try await broker.syncRithmicAccount(
                    connectionId: connectionId,
                    mappingId: mappingId,
                    password: nil
                )
            }
            accountsByConnection[connectionId] = response.accounts
            let newIds = response.summary.newTradeIds
            await refreshTradesAfterImport(newTradeIds: newIds)
            if response.summary.ok {
                noteBrokerIntegrationChanged()
                presentMessage(BrokerIntegrationDisplay.importResultMessage(newTradeCount: newIds.count), error: false)
                if !newIds.isEmpty {
                    pendingReviewTradeIDs = newIds.map { TradeID($0) }
                    showsReviewImportedTrades = true
                }
            } else if provider == .rithmic,
                      response.summary.errorCode == "rithmic_password_required"
            {
                presentRithmicImportReauth(connectionId: connectionId, mappingId: mappingId)
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

    func collapsedSummary(for provider: BrokerIntegrationProvider) -> String {
        switch provider {
        case .tradovate:
            switch tradovateLoadPhase {
            case .loading where tradovateConnections.isEmpty:
                return "Loading…"
            case .failed where tradovateConnections.isEmpty:
                return "Couldn’t load"
            default:
                return summaryForConnections(tradovateConnections)
            }
        case .rithmic:
            if case .loading = rithmicConnectionsLoadPhase, rithmicConnections.isEmpty {
                return "Loading…"
            }
            if case .failed = rithmicConnectionsLoadPhase, rithmicConnections.isEmpty {
                return "Couldn’t load connections"
            }
            switch rithmicConnectCapabilitiesPhase {
            case .loading where rithmicConnections.isEmpty:
                return "Checking availability…"
            case .failed where rithmicConnections.isEmpty:
                return "Couldn’t load availability"
            case .loaded:
                if rithmicConnectCapabilities?.showConnectUi != true, rithmicConnections.isEmpty {
                    return "Not available on this server"
                }
                if rithmicConnections.isEmpty {
                    return "Not connected"
                }
                return summaryForConnections(rithmicConnections)
            default:
                return summaryForConnections(rithmicConnections)
            }
        }
    }

    private func summaryForConnections(_ connections: [TradovateConnectionSummary]) -> String {
        let active = connections.filter(\.isActiveForBrokerUI)
        guard !active.isEmpty else { return "Not connected" }
        let accountCount = active.reduce(0) { partial, connection in
            partial + accounts(for: connection.id).count
        }
        let accountsPhrase = accountCount == 1 ? "1 account" : "\(accountCount) accounts"
        if active.contains(where: \.connected) {
            return "Connected · \(accountsPhrase)"
        }
        if active.contains(where: { $0.status == .reconnectRequired }) {
            return "Reconnect needed · \(accountsPhrase)"
        }
        return "\(accountsPhrase)"
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

    private func noteBrokerIntegrationChanged() {
        BrokerIntegrationMutationStore.shared.noteBrokerIntegrationChanged()
        BrokerImportEligibilityStore.shared.refresh(fromUserAction: false)
    }
}
