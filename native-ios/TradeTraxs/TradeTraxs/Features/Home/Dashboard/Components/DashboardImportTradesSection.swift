import SwiftUI

/// One Dashboard row under Daily Check-In. Account actions open in a sheet.
struct DashboardImportTradesSection: View {
    let data: DataEnvironment
    @Bindable var store: BrokerImportEligibilityStore
    let navigationCoordinator: NavigationCoordinator

    @State private var showsAccounts = false
    @State private var importFlow = BrokerImportFlowModel()
    @State private var brokerViewModel: BrokerIntegrationsViewModel?
    @State private var manageAccountsViewModel: ManageAccountsViewModel?
    @State private var tradingAccounts: [TradingAccount] = []
    @State private var reviewTradeIDs: [TradeID] = []
    @State private var showsReview = false
    @State private var rithmicReauthTarget: BrokerImportEligibilityTarget?
    @State private var showsRithmicReauth = false
    @State private var rithmicReauthUsername: String?

    @Environment(\.themeColors) private var colors

    var body: some View {
        DashboardQuickActionRow(
            title: "Broker Integration",
            subtitle: rowSubtitle,
            accessibilityIdentifier: "dashboard.brokerIntegration",
            accessibilityHint: "Shows connected broker accounts"
        ) {
            ZStack {
                Circle()
                    .fill(colors.accent.opacity(0.12))
                    .frame(
                        width: DashboardQuickActionStyle.iconDiameter,
                        height: DashboardQuickActionStyle.iconDiameter
                    )
                Image(systemName: "link")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(colors.accent)
            }
        } onTap: {
            ExperienceHaptics.play(.selection)
            showsAccounts = true
        }
        .sheet(isPresented: $showsAccounts) {
            accountsSheet
        }
        .task(id: showsAccounts) {
            guard showsAccounts else { return }
            ensureBrokerViewModel()
            await loadTradingAccountsIfNeeded()
            await brokerViewModel?.refreshAll(announceChange: false)
        }
    }

    private var rowSubtitle: String {
        let count = max(store.linkedAccountCount, store.linkedAccounts.count)
        if count > 0 {
            return count == 1 ? "1 account connected" : "\(count) accounts connected"
        }
        if store.hasSupportedConnection || store.connectionCount > 0 {
            return "Link a broker account to import trades"
        }
        return "Connect Tradovate or Rithmic"
    }

    private var accountsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                    if !liveTargets.isEmpty {
                        liveBrokerRows
                    } else if !store.linkedAccounts.isEmpty {
                        linkedBrokerRows
                    } else if accountsStillLoading {
                        loadingRow
                    } else if hasConnectedBroker {
                        needsLinkingCard
                    } else {
                        emptyStateRows
                    }
                }
                .padding(ExperienceSpacing.md)
            }
            .experienceScreenBackground()
            .experienceNavigationTitle("Broker Integration")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showsAccounts = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .fullScreenCover(isPresented: $importFlow.isPresented) {
            BrokerImportProgressView(
                model: importFlow,
                onReviewImportedTrades: { ids in
                    reviewTradeIDs = ids
                    showsReview = true
                },
                onEditSingleImportedTrade: { _ in },
                onClose: {}
            )
        }
        .sheet(isPresented: $showsReview) {
            BrokerImportedTradesReviewView(tradeIDs: reviewTradeIDs, data: data) {
                reviewTradeIDs = []
            }
        }
        .sheet(isPresented: $showsRithmicReauth, onDismiss: {
            rithmicReauthTarget = nil
            rithmicReauthUsername = nil
        }) {
            RithmicConnectSheet(
                mode: .importTrades,
                isBusy: false,
                systemChoices: [],
                prefilledUsername: rithmicReauthUsername,
                prefilledSystemName: nil,
                locksUsername: rithmicReauthUsername != nil,
                onSubmit: { _, password, _ in
                    guard let target = rithmicReauthTarget else { return }
                    showsRithmicReauth = false
                    importFlow.startImport(target: target, data: data, rithmicPassword: password)
                }
            )
        }
        .onChange(of: importFlow.pendingRithmicPasswordTarget?.mappingId) { _, mappingId in
            guard mappingId != nil, let target = importFlow.pendingRithmicPasswordTarget else { return }
            rithmicReauthTarget = target
            Task { await loadRithmicUsername(for: target.connectionId) }
            showsRithmicReauth = true
        }
    }

    private var loadingRow: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            ProgressView()
                .controlSize(.small)
            Text("Loading broker connections…")
                .experienceStyle(.footnote, color: colors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DashboardQuickActionStyle.horizontalPadding)
        .padding(.vertical, DashboardQuickActionStyle.verticalPadding)
        .background(rowBackground)
    }

    private var linkedBrokerRows: some View {
        VStack(spacing: ExperienceSpacing.sm) {
            ForEach(store.linkedAccounts) { target in
                linkedAccountCard(target)
            }
        }
    }

    private var liveBrokerRows: some View {
        VStack(spacing: ExperienceSpacing.sm) {
            ForEach(liveTargets) { target in
                linkedAccountCard(target)
            }
        }
    }

    /// Connected broker accounts from the same source as Settings → Broker Integrations.
    private var liveTargets: [BrokerImportEligibilityTarget] {
        guard let brokerViewModel else { return [] }
        var targets: [BrokerImportEligibilityTarget] = []
        func append(
            provider: BrokerIntegrationProvider,
            connections: [TradovateConnectionSummary]
        ) {
            for connection in connections where connection.isActiveForBrokerUI {
                for account in brokerViewModel.accounts(for: connection.id) {
                    targets.append(
                        BrokerImportEligibilityTarget(
                            provider: provider,
                            mappingId: account.id,
                            connectionId: connection.id,
                            brokerAccountLabel: account.displayTitle,
                            tradetraxsAccountName: account.tradetraxsAccountName
                        )
                    )
                }
            }
        }
        append(provider: .tradovate, connections: brokerViewModel.tradovateConnections)
        append(provider: .rithmic, connections: brokerViewModel.rithmicConnections)
        return targets
    }

    private var accountsStillLoading: Bool {
        guard let brokerViewModel else { return true }
        if !brokerViewModel.isRefreshingAccounts.isEmpty { return true }
        switch brokerViewModel.tradovateLoadPhase {
        case .idle, .loading:
            return true
        case .loaded, .failed:
            break
        }
        switch brokerViewModel.rithmicConnectionsLoadPhase {
        case .idle, .loading:
            return true
        case .loaded, .failed:
            return false
        }
    }

    private var hasConnectedBroker: Bool {
        if store.hasSupportedConnection || store.connectionCount > 0 || store.needsAccountLinking {
            return true
        }
        guard let brokerViewModel else { return false }
        return brokerViewModel.tradovateConnections.contains(where: \.isActiveForBrokerUI)
            || brokerViewModel.rithmicConnections.contains(where: \.isActiveForBrokerUI)
    }

    private func linkedAccountCard(_ target: BrokerImportEligibilityTarget) -> some View {
        let integration = integrationContext(for: target)
        return VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            Text(target.brokerAccountLabel)
                .experienceStyle(.subheadline, color: colors.primaryText)
                .fontWeight(.semibold)
                .lineLimit(1)

            Text(
                BrokerIntegrationDisplay.brokerImportMetadataLine(
                    provider: target.provider,
                    tradetraxsAccountName: target.tradetraxsAccountName,
                    tradingAccounts: tradingAccounts
                )
            )
            .experienceStyle(.footnote, color: colors.secondaryText)
            .lineLimit(2)

            if let integration {
                Text(statusLine(connection: integration.connection, account: integration.account))
                    .experienceStyle(.caption, color: colors.tertiaryText)
            }

            if let integration, !integration.account.hasTradetraxsMapping {
                Button {
                    openBrokerIntegrations()
                } label: {
                    Label("Link Broker Account", systemImage: "link")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colors.accent)
                .padding(.top, ExperienceSpacing.xxs)
            } else if prefersReconnect(integration) {
                Button {
                    openBrokerIntegrations()
                } label: {
                    Text(BrokerSyncPresentation.reconnectPrimaryActionTitle(provider: target.provider))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colors.accent)
                .padding(.top, ExperienceSpacing.xxs)
            } else {
                Button {
                    importFlow.startImport(target: target, data: data)
                } label: {
                    Label(importActionTitle(for: target, integration: integration), systemImage: "square.and.arrow.down")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colors.accent)
                .padding(.top, ExperienceSpacing.xxs)
                .disabled(importFlow.isPresented)
            }
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.vertical, ExperienceSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .overlay(rowBorder)
        .accessibilityIdentifier("dashboard.importTrades.account.\(target.mappingId)")
    }

    private var needsLinkingCard: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Your broker is connected. Link a discovered account to import trades.")
                .experienceStyle(.footnote, color: colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                openBrokerIntegrations()
            } label: {
                Label("Link Broker Account", systemImage: "link")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(colors.accent)
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.vertical, ExperienceSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .overlay(rowBorder)
    }

    private var emptyStateRows: some View {
        VStack(spacing: ExperienceSpacing.sm) {
            DashboardQuickActionRow(
                title: "Connect Broker",
                subtitle: "Sync trades from Tradovate or Rithmic",
                accessibilityIdentifier: "dashboard.importTrades.connectBroker"
            ) {
                ZStack {
                    Circle()
                        .fill(colors.accent.opacity(0.12))
                        .frame(
                            width: DashboardQuickActionStyle.iconDiameter,
                            height: DashboardQuickActionStyle.iconDiameter
                        )
                    Image(systemName: "link")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(colors.accent)
                }
            } onTap: {
                ExperienceHaptics.play(.selection)
                openBrokerIntegrations()
            }

            DashboardQuickActionRow(
                title: "Import CSV",
                subtitle: "Upload a trade history file",
                accessibilityIdentifier: "dashboard.importTrades.importCSV"
            ) {
                ZStack {
                    Circle()
                        .fill(colors.accent.opacity(0.12))
                        .frame(
                            width: DashboardQuickActionStyle.iconDiameter,
                            height: DashboardQuickActionStyle.iconDiameter
                        )
                    Image(systemName: "doc.text")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(colors.accent)
                }
            } onTap: {
                ExperienceHaptics.play(.selection)
                TradeEntryLaunchIntent.prepare(hubTab: .csv)
                navigationCoordinator.present(fullScreen: .addTrade)
            }
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: DashboardQuickActionStyle.cornerRadius, style: .continuous)
            .fill(colors.surfacePrimary)
    }

    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: DashboardQuickActionStyle.cornerRadius, style: .continuous)
            .stroke(colors.border, lineWidth: 1)
    }

    private func ensureBrokerViewModel() {
        guard brokerViewModel == nil else { return }
        let manage = ManageAccountsViewModel(
            trades: data.trades,
            session: data.session,
            detailCache: data.detailCache
        )
        manageAccountsViewModel = manage
        brokerViewModel = BrokerIntegrationsViewModel(
            broker: data.brokerIntegrations,
            trades: data.trades,
            manageAccounts: manage,
            session: data.session,
            detailCache: data.detailCache,
            onOpenCSVImport: {
                TradeEntryLaunchIntent.prepare(hubTab: .csv)
                navigationCoordinator.present(fullScreen: .addTrade)
            }
        )
        manage.loadIfNeeded()
    }

    private func integrationContext(
        for target: BrokerImportEligibilityTarget
    ) -> (connection: TradovateConnectionSummary, account: BrokerIntegrationAccount)? {
        guard let brokerViewModel else { return nil }
        let connections = target.provider == .tradovate
            ? brokerViewModel.tradovateConnections
            : brokerViewModel.rithmicConnections
        guard let connection = connections.first(where: { $0.id == target.connectionId }) else { return nil }
        guard let account = brokerViewModel.accounts(for: connection.id).first(where: { $0.id == target.mappingId })
        else { return nil }
        return (connection, account)
    }

    private func statusLine(
        connection: TradovateConnectionSummary,
        account: BrokerIntegrationAccount
    ) -> String {
        if connection.status == .reconnectRequired {
            return "Reconnect required"
        }
        if BrokerImportActionAvailability.isSyncInProgressFromPersisted(account: account) {
            return "Sync in progress"
        }
        if BrokerImportActionAvailability.showsRetryImportLabel(connection: connection, account: account) {
            return "Last import needs retry"
        }
        return "Ready to import"
    }

    private func prefersReconnect(
        _ integration: (connection: TradovateConnectionSummary, account: BrokerIntegrationAccount)?
    ) -> Bool {
        guard let integration else { return false }
        if integration.connection.status == .reconnectRequired { return true }
        return BrokerImportActionAvailability.prefersReconnectAction(
            connection: integration.connection,
            account: integration.account,
            sessionReconnectMappingId: nil
        )
    }

    private func importActionTitle(
        for target: BrokerImportEligibilityTarget,
        integration: (connection: TradovateConnectionSummary, account: BrokerIntegrationAccount)?
    ) -> String {
        guard let integration else { return "Import Trades" }
        if BrokerImportActionAvailability.showsRetryImportLabel(
            connection: integration.connection,
            account: integration.account
        ) {
            return "Retry Import"
        }
        return "Import Trades"
    }

    private func openBrokerIntegrations() {
        navigationCoordinator.open(.settingsStack([.home, .tradingAccounts, .brokerIntegrations]))
    }

    private func loadTradingAccountsIfNeeded() async {
        guard let userID = await data.session.currentUserID else { return }
        let profileID = ProfileID(userID.rawValue)
        if let cached = SessionAccountsStore.shared.cached(for: profileID), !cached.isEmpty {
            tradingAccounts = cached
            return
        }
        if let seeded = data.detailCache.accounts(for: profileID), !seeded.isEmpty {
            tradingAccounts = seeded
            return
        }
        do {
            tradingAccounts = try await SessionAccountsStore.shared.accounts(
                for: profileID,
                detailCache: data.detailCache,
                repository: data.trades,
                requiresFullOwnerSnapshot: true,
                viewerProfileID: profileID
            )
        } catch {
            tradingAccounts = SessionAccountsStore.shared.cached(for: profileID) ?? []
        }
    }

    private func loadRithmicUsername(for connectionId: String) async {
        do {
            let response = try await data.brokerIntegrations.listRithmicConnections()
            rithmicReauthUsername = response.connections
                .first(where: { $0.id == connectionId })?
                .brokerLoginUsername
        } catch {
            rithmicReauthUsername = nil
        }
    }
}
