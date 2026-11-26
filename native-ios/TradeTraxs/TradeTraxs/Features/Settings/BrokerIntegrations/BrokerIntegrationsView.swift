import SwiftUI

struct BrokerIntegrationsView: View {
    @State private var viewModel: BrokerIntegrationsViewModel
    @State private var manageAccountsViewModel: ManageAccountsViewModel
    @State private var linkTarget: BrokerIntegrationLinkTarget?
    @State private var createLinkTarget: BrokerIntegrationCreateLinkTarget?
    @State private var disconnectTarget: BrokerDisconnectTarget?
    @State private var expandedBrokers: Set<BrokerIntegrationProvider> = []
    @State private var expandedConnections: Set<String> = []
    @State private var collapsedConnections: Set<String> = []
    @State private var linkPromptGate = BrokerIntegrationLinkPromptGate()

    @Environment(\.themeColors) private var colors

    private let data: DataEnvironment
    private let navigationCoordinator: NavigationCoordinator?

    private enum BrokerDisconnectTarget: Identifiable {
        case tradovate(TradovateConnectionSummary)
        case rithmic(TradovateConnectionSummary)

        var id: String {
            switch self {
            case .tradovate(let connection), .rithmic(let connection):
                return connection.id
            }
        }

        var provider: BrokerIntegrationProvider {
            switch self {
            case .tradovate: return .tradovate
            case .rithmic: return .rithmic
            }
        }

        var connection: TradovateConnectionSummary {
            switch self {
            case .tradovate(let connection), .rithmic(let connection):
                return connection
            }
        }
    }

    init(data: DataEnvironment, navigationCoordinator: NavigationCoordinator? = nil) {
        self.data = data
        self.navigationCoordinator = navigationCoordinator
        let manage = ManageAccountsViewModel(
            trades: data.trades,
            session: data.session,
            detailCache: data.detailCache
        )
        _manageAccountsViewModel = State(initialValue: manage)
        _viewModel = State(
            initialValue: BrokerIntegrationsViewModel(
                broker: data.brokerIntegrations,
                trades: data.trades,
                manageAccounts: manage,
                session: data.session,
                detailCache: data.detailCache,
                onOpenCSVImport: {
                    navigationCoordinator?.openCompose(.importCSV)
                }
            )
        )
    }

    var body: some View {
        List {
            Section {
                BrokerIntegrationsSecurityDisclaimer()
                    .experienceDashboardListRow()
            }

            if let oauthError = viewModel.oauthErrorMessage {
                Section {
                    brokerInlineBanner(message: oauthError, isError: true) {
                        if !viewModel.isBrokerConnectionMutationActive {
                            Button("Retry Connect") {
                                viewModel.promptConnectTradovate()
                            }
                            .font(.footnote.weight(.semibold))
                            .buttonStyle(.experiencePlain)
                        }
                    }
                }
            }

            if let message = viewModel.actionMessage {
                Section {
                    brokerInlineBanner(message: message, isError: viewModel.actionIsError) {
                        importActionBanner
                    }
                }
            }

            Section {
                ForEach(BrokerIntegrationsCatalog.providers, id: \.self) { provider in
                    brokerProviderCard(provider)
                        .brokerIntegrationsCardListRow()
                }
            }

            Section {
                BrokerIntegrationComingSoonFooter()
                    .listRowSeparator(.hidden)
            }
            .listRowBackground(Color.clear)
        }
        .experienceInsetGroupedListStyle(pageBackground: true)
        .listSectionSpacing(BrokerIntegrationProviderOptionsLayout.listSectionSpacing)
        .contentMargins(.top, ExperienceSpacing.xxs, for: .scrollContent)
        .experienceNavigationTitle("Broker Integrations")
        .background {
            BrokerIntegrationConnectionCoordinator(
                viewModel: viewModel,
                manageAccountsViewModel: manageAccountsViewModel,
                data: data,
                linkTarget: $linkTarget,
                createLinkTarget: $createLinkTarget,
                linkPromptGate: linkPromptGate,
                showsImportedTradesReview: true
            )
        }
        .brokerIntegrationAutoLinkPrompt(
            viewModel: viewModel,
            gate: linkPromptGate,
            linkTarget: $linkTarget,
            createLinkTarget: $createLinkTarget,
            onExpandConnectedLogin: { provider, connectionID in
                expandedBrokers.insert(provider)
                expandedConnections.insert(connectionID)
                collapsedConnections.remove(connectionID)
            }
        )
        .confirmationDialog(
            disconnectDialogTitle,
            isPresented: Binding(
                get: { disconnectTarget != nil },
                set: { if !$0 { disconnectTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                guard let target = disconnectTarget else { return }
                disconnectTarget = nil
                Task { await viewModel.disconnect(provider: target.provider, connectionId: target.connection.id) }
            }
            Button("Cancel", role: .cancel) {
                disconnectTarget = nil
            }
        } message: {
            Text("Your TradeTraxs accounts and imported trades will stay in the journal.")
        }
        .sheet(isPresented: $viewModel.showsTradovateNoTradeHistorySheet) {
            brokerNoTradeHistorySheet
        }
        .onAppear {
            BrokerIntegrationsLoadPriorityGate.setScreenActive(true)
            manageAccountsViewModel.loadIfNeeded()
            Task { await viewModel.refreshAll() }
        }
        .onDisappear {
            BrokerIntegrationsLoadPriorityGate.setScreenActive(false)
        }
        .accessibilityIdentifier("settings.brokerIntegrations")
    }

    @ViewBuilder
    private var brokerNoTradeHistorySheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                Text(BrokerSyncPresentation.noAvailableTradeHistoryTitle())
                    .experienceStyle(.headline, color: colors.primaryText)
                Text(BrokerSyncPresentation.noAvailableTradeHistoryDetail())
                    .experienceStyle(.body, color: colors.secondaryText)
                Spacer(minLength: ExperienceSpacing.sm)
                ExperienceButton(title: "Import CSV", kind: .primary) {
                    viewModel.showsTradovateNoTradeHistorySheet = false
                    viewModel.openTradovatePerformanceCSVImport()
                }
                ExperienceButton(title: "Done", kind: .secondary) {
                    viewModel.showsTradovateNoTradeHistorySheet = false
                }
            }
            .padding(ExperienceSpacing.lg)
            .experienceScreenBackground()
            .experienceNavigationTitle("Import Trades")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        viewModel.showsTradovateNoTradeHistorySheet = false
                    }
                }
            }
        }
        .experienceSheetChrome(detents: [.medium])
    }

    private var disconnectDialogTitle: String {
        switch disconnectTarget?.provider {
        case .rithmic: return "Disconnect Rithmic?"
        case .tradovate, .none: return "Disconnect Tradovate?"
        }
    }

    @ViewBuilder
    private func brokerInlineBanner(
        message: String,
        isError: Bool,
        @ViewBuilder actions: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text(message)
                .experienceStyle(.footnote, color: isError ? colors.primaryText : colors.secondaryText)
            actions()
        }
        .experienceDashboardListRow()
    }

    @ViewBuilder
    private var importActionBanner: some View {
        if let reconnect = viewModel.importReconnectPrompt,
           !viewModel.isImportingTrades(mappingId: reconnect.mappingId)
        {
            Button("Reconnect") {
                viewModel.reconnectBrokerImport(from: reconnect)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(colors.accent)
            .buttonStyle(.experiencePlain)
            .accessibilityIdentifier("brokerIntegrations.importReconnectBanner")
        } else if let retry = viewModel.importRetryPrompt,
                  !viewModel.isImportingTrades(mappingId: retry.mappingId)
        {
            Button("Try Again") {
                Task {
                    await viewModel.importTrades(
                        provider: retry.provider,
                        connectionId: retry.connectionId,
                        mappingId: retry.mappingId
                    )
                }
            }
            .font(.footnote.weight(.semibold))
            .buttonStyle(.experiencePlain)
            .accessibilityIdentifier("brokerIntegrations.importRetryBanner")
        }
    }

    @ViewBuilder
    private func brokerProviderCard(_ provider: BrokerIntegrationProvider) -> some View {
        let isExpanded = expandedBrokers.contains(provider)

        BrokerIntegrationCompactCard {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                Button {
                    ExperienceHaptics.play(.selection)
                    if isExpanded {
                        expandedBrokers.remove(provider)
                    } else {
                        expandedBrokers.insert(provider)
                    }
                } label: {
                    HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
                        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                            Text(BrokerIntegrationsCatalog.displayName(for: provider))
                                .experienceStyle(.subheadline, color: colors.primaryText)
                            Text(viewModel.collapsedSummary(for: provider))
                                .font(ExperienceTypography.caption)
                                .foregroundStyle(colors.secondaryText)
                        }
                        Spacer(minLength: ExperienceSpacing.sm)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(colors.tertiaryText)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.experiencePlain)
                .accessibilityIdentifier("brokerIntegrations.section.\(provider.rawValue)")

                if isExpanded {
                    switch provider {
                    case .tradovate:
                        tradovateProviderBody
                    case .rithmic:
                        rithmicProviderBody
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var tradovateProviderBody: some View {
        switch viewModel.tradovateLoadPhase {
        case .loading where viewModel.tradovateConnections.isEmpty:
            brokerLoadingRow("Loading Tradovate…")
        case .failed(let message) where viewModel.tradovateConnections.isEmpty:
            brokerFailedRow(message: message)
        default:
            EmptyView()
        }

        if viewModel.tradovateConnections.isEmpty,
           viewModel.tradovateLoadPhase != .loading
        {
            BrokerIntegrationSettingsButton(
                title: "Connect Tradovate",
                icon: .create,
                isPrimary: true,
                isEnabled: !viewModel.isBrokerConnectionMutationActive,
                accessibilityIdentifier: "brokerIntegrations.connectTradovate"
            ) {
                viewModel.promptConnectTradovate()
            }
        }

        ForEach(viewModel.tradovateConnections) { connection in
            brokerConnectionCard(
                provider: .tradovate,
                connection: connection,
                connections: viewModel.tradovateConnections
            )
        }

        if !viewModel.tradovateConnections.isEmpty {
            connectAnotherLoginButton(title: "New Tradovate Integration") {
                viewModel.promptConnectTradovate()
            }
        }
    }

    @ViewBuilder
    private var rithmicProviderBody: some View {
        switch viewModel.rithmicConnectionsLoadPhase {
        case .loading where viewModel.rithmicConnections.isEmpty:
            brokerLoadingRow("Loading Rithmic connections…")
        case .failed(let message) where viewModel.rithmicConnections.isEmpty:
            brokerFailedRow(message: message)
        default:
            EmptyView()
        }

        ForEach(viewModel.rithmicConnections) { connection in
            brokerConnectionCard(
                provider: .rithmic,
                connection: connection,
                connections: viewModel.rithmicConnections
            )
        }

        rithmicConnectAvailabilityBody

        if !viewModel.rithmicConnections.isEmpty {
            connectAnotherLoginButton(title: "New Rithmic Integration") {
                viewModel.presentRithmicConnect()
            }
        }
    }

    @ViewBuilder
    private var rithmicConnectAvailabilityBody: some View {
        switch viewModel.rithmicConnectCapabilitiesPhase {
        case .loading where viewModel.rithmicConnections.isEmpty:
            brokerLoadingRow("Checking Rithmic availability…")
        case .failed where viewModel.rithmicConnections.isEmpty:
            brokerFailedRow(message: "Couldn’t load Rithmic availability.")
        case .loaded:
            if viewModel.isRithmicConnectUIAvailable {
                if viewModel.rithmicConnections.isEmpty {
                    BrokerIntegrationSettingsButton(
                        title: "Connect Rithmic",
                        icon: .create,
                        isPrimary: true,
                        isEnabled: !viewModel.isBrokerConnectionMutationActive,
                        accessibilityIdentifier: "brokerIntegrations.connectRithmic"
                    ) {
                        viewModel.presentRithmicConnect()
                    }
                }
            } else if viewModel.rithmicConnections.isEmpty {
                Text(rithmicUnavailableLabel)
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }
        default:
            EmptyView()
        }
    }

    private func connectAnotherLoginButton(
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        BrokerIntegrationSettingsButton(
            title: title,
            isEnabled: !viewModel.isBrokerConnectionMutationActive,
            action: action
        )
    }

    @ViewBuilder
    private func brokerConnectionCard(
        provider: BrokerIntegrationProvider,
        connection: TradovateConnectionSummary,
        connections: [TradovateConnectionSummary]
    ) -> some View {
        let expanded = isConnectionExpanded(connection.id, connections: connections)
        let accounts = viewModel.accounts(for: connection.id)
        let loginNeedsReconnect = connectionRequiresLoginReconnect(
            provider: provider,
            connection: connection,
            accounts: accounts
        )

        BrokerIntegrationCompactCard {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                Button {
                    ExperienceHaptics.play(.selection)
                    toggleConnectionExpansion(connection.id, connections: connections)
                } label: {
                    HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                            Text(connection.label)
                                .experienceStyle(.subheadline, color: colors.primaryText)
                            if let environment = connectionEnvironmentLabel(connection) {
                                Text(environment)
                                    .font(ExperienceTypography.caption)
                                    .foregroundStyle(colors.secondaryText)
                            }
                        }
                        Spacer(minLength: ExperienceSpacing.xs)
                        if connection.connected, !loginNeedsReconnect {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(colors.accent)
                                .accessibilityLabel("Connected")
                        }
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(colors.tertiaryText)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.experiencePlain)

                if expanded {
                    if loginNeedsReconnect {
                        Text(BrokerSyncPresentation.reconnectRequiredMessage(provider: provider))
                            .font(ExperienceTypography.caption)
                            .foregroundStyle(colors.loss)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("brokerIntegrations.reconnectWarning.\(connection.id)")
                    }

                    if viewModel.isRefreshingAccounts.contains(connection.id) {
                        brokerLoadingRow("Refreshing accounts…")
                    } else if accounts.isEmpty {
                        Text("No broker accounts returned. Try Refresh Accounts.")
                            .font(ExperienceTypography.caption)
                            .foregroundStyle(colors.secondaryText)
                    } else {
                        ForEach(accounts) { account in
                            brokerDiscoveredAccountCard(
                                provider: provider,
                                connection: connection,
                                account: account,
                                accounts: accounts
                            )
                        }
                    }

                    if connection.isActiveForBrokerUI {
                        if connection.connected {
                            BrokerIntegrationSettingsButton(
                                title: "Refresh Accounts",
                                isEnabled: !viewModel.isBrokerConnectionMutationActive
                            ) {
                                Task {
                                    await viewModel.loadAccounts(
                                        provider: provider,
                                        connectionId: connection.id,
                                        forceRefresh: provider == .tradovate
                                    )
                                }
                            }
                        }

                        BrokerIntegrationTextAction(
                            title: "Disconnect",
                            isDestructive: true,
                            isEnabled: !viewModel.isBrokerConnectionMutationActive
                        ) {
                            disconnectTarget = provider == .tradovate
                                ? .tradovate(connection)
                                : .rithmic(connection)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func brokerDiscoveredAccountCard(
        provider: BrokerIntegrationProvider,
        connection: TradovateConnectionSummary,
        account: BrokerIntegrationAccount,
        accounts: [BrokerIntegrationAccount]
    ) -> some View {
        let loginNeedsReconnect = connectionRequiresLoginReconnect(
            provider: provider,
            connection: connection,
            accounts: accounts
        )
        let showsReconnect = isPrimaryReconnectAccount(
            account: account,
            accounts: accounts,
            loginNeedsReconnect: loginNeedsReconnect
        )

        BrokerIntegrationCompactCard {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                accountTitleBlock(
                    account: account,
                    showsReconnect: showsReconnect,
                    provider: provider,
                    connection: connection
                )

                if let linked = linkedSummaryLine(for: account) {
                    Text(linked)
                        .font(ExperienceTypography.caption)
                        .foregroundStyle(colors.secondaryText)
                }

                if !loginNeedsReconnect {
                    accountActions(provider: provider, connection: connection, account: account)
                }
            }
        }
    }

    @ViewBuilder
    private func accountTitleBlock(
        account: BrokerIntegrationAccount,
        showsReconnect: Bool,
        provider: BrokerIntegrationProvider,
        connection: TradovateConnectionSummary
    ) -> some View {
        let masked = BrokerIntegrationDisplay.maskedBrokerAccountNumber(
            account.externalAccountId,
            name: account.externalAccountName,
            displayName: account.externalDisplayName
        )
        let typeLabel = BrokerIntegrationDisplay.brokerAccountTypeLabel(metadata: account.metadata)
        let title = account.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let showsMasked = !masked.isEmpty && masked != title

        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                Text(title)
                    .experienceStyle(.subheadline, color: colors.primaryText)
                if showsMasked {
                    Text(masked)
                        .font(ExperienceTypography.caption)
                        .foregroundStyle(colors.tertiaryText)
                }
            }
            Spacer(minLength: ExperienceSpacing.xs)
            if showsReconnect {
                Button("Reconnect") {
                    performLoginReconnect(provider: provider, connection: connection)
                }
                .font(ExperienceTypography.footnote.weight(.semibold))
                .foregroundStyle(colors.accent)
                .buttonStyle(.experiencePlain)
                .accessibilityIdentifier("brokerIntegrations.reconnect.\(connection.id)")
            } else if let typeLabel {
                Text(typeLabel)
                    .font(ExperienceTypography.caption)
                    .foregroundStyle(colors.secondaryText)
            }
        }
    }

    private func linkedSummaryLine(for account: BrokerIntegrationAccount) -> String? {
        if let linked = BrokerIntegrationDisplay.linkedTradeTraxsLine(
            for: account,
            tradingAccounts: manageAccountsViewModel.accounts
        ) {
            return linked.replacingOccurrences(of: "Linked to: ", with: "Linked · ")
        }
        guard !account.hasTradetraxsMapping else { return "Linked" }
        return "Not linked"
    }

    @ViewBuilder
    private func accountActions(
        provider: BrokerIntegrationProvider,
        connection: TradovateConnectionSummary,
        account: BrokerIntegrationAccount
    ) -> some View {
        if viewModel.showsManualImportActions(connection: connection, account: account) {
            BrokerIntegrationSettingsButton(
                title: viewModel.isImportBusy(for: account)
                    ? "Importing…"
                    : viewModel.manualImportActionTitle(connection: connection, account: account),
                isPrimary: true,
                isEnabled: !viewModel.isImportBusy(for: account),
                isLoading: viewModel.isImportBusy(for: account),
                accessibilityIdentifier: "brokerIntegrations.importTrades.\(account.id)"
            ) {
                Task {
                    await viewModel.importTrades(
                        provider: provider,
                        connectionId: connection.id,
                        mappingId: account.id
                    )
                }
            }
        } else if !account.hasTradetraxsMapping, connection.connected {
            BrokerIntegrationSettingsButton(title: "Link Account") {
                linkPromptGate.recordPresentation(mappingID: account.id)
                linkTarget = BrokerIntegrationLinkTarget(
                    provider: provider,
                    connectionId: connection.id,
                    account: account
                )
            }
        }
    }

    private func connectionRequiresLoginReconnect(
        provider: BrokerIntegrationProvider,
        connection: TradovateConnectionSummary,
        accounts: [BrokerIntegrationAccount]
    ) -> Bool {
        if connection.status == .reconnectRequired { return true }
        return accounts.contains { account in
            viewModel.resolvedImportReconnectPrompt(
                provider: provider,
                connection: connection,
                account: account
            ) != nil
        }
    }

    private func isPrimaryReconnectAccount(
        account: BrokerIntegrationAccount,
        accounts: [BrokerIntegrationAccount],
        loginNeedsReconnect: Bool
    ) -> Bool {
        guard loginNeedsReconnect, let first = accounts.first else { return false }
        return first.id == account.id
    }

    private func performLoginReconnect(
        provider: BrokerIntegrationProvider,
        connection: TradovateConnectionSummary
    ) {
        if connection.status == .reconnectRequired {
            switch provider {
            case .tradovate:
                viewModel.promptConnectTradovate(reconnectConnectionId: connection.id)
            case .rithmic:
                viewModel.presentRithmicConnect(reconnectConnectionId: connection.id)
            }
            return
        }
        let accounts = viewModel.accounts(for: connection.id)
        guard let account = accounts.first,
              let prompt = viewModel.resolvedImportReconnectPrompt(
                  provider: provider,
                  connection: connection,
                  account: account
              )
        else { return }
        viewModel.reconnectBrokerImport(from: prompt)
    }

    private func brokerLoadingRow(_ text: String) -> some View {
        HStack(spacing: ExperienceSpacing.sm) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .experienceStyle(.footnote, color: colors.secondaryText)
        }
    }

    private func brokerFailedRow(message: String) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text(message)
                .experienceStyle(.footnote, color: colors.secondaryText)
            Button("Retry") {
                Task { await viewModel.refreshAll() }
            }
            .font(.footnote.weight(.semibold))
            .buttonStyle(.experiencePlain)
        }
    }

    private func isConnectionExpanded(_ id: String, connections: [TradovateConnectionSummary]) -> Bool {
        if expandedConnections.contains(id) { return true }
        if collapsedConnections.contains(id) { return false }
        return false
    }

    private func toggleConnectionExpansion(_ id: String, connections: [TradovateConnectionSummary]) {
        let currentlyExpanded = isConnectionExpanded(id, connections: connections)
        if currentlyExpanded {
            collapsedConnections.insert(id)
            expandedConnections.remove(id)
        } else {
            collapsedConnections.remove(id)
            expandedConnections.insert(id)
        }
    }

    private func connectionEnvironmentLabel(_ connection: TradovateConnectionSummary) -> String? {
        guard let env = connection.apiEnvironment?.trimmingCharacters(in: .whitespacesAndNewlines),
              !env.isEmpty
        else { return nil }
        return env.uppercased()
    }

    private var rithmicUnavailableLabel: String {
        guard let caps = viewModel.rithmicConnectCapabilities else {
            return "Rithmic connect is unavailable on this server."
        }
        if !caps.userConnectEnabled {
            return "Rithmic user connection is disabled on this server."
        }
        if caps.apiEnvironment == "production", !caps.productionUserAuthConfirmed {
            return "Production Rithmic login is not approved yet."
        }
        if caps.apiEnvironment != "test", !caps.showConnectUi {
            return "Only the supported Rithmic Test environment is enabled for connect."
        }
        return "Rithmic connect is unavailable until server protocol configuration is complete."
    }
}