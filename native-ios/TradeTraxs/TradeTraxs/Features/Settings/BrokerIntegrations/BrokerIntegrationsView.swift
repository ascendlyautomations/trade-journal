import SwiftUI

struct BrokerIntegrationsView: View {
    @State private var viewModel: BrokerIntegrationsViewModel
    @State private var manageAccountsViewModel: ManageAccountsViewModel
    @State private var linkTarget: BrokerIntegrationLinkTarget?
    @State private var createLinkTarget: BrokerIntegrationCreateLinkTarget?
    @State private var disconnectTarget: BrokerDisconnectTarget?
    @State private var brokerSearchText = ""
    @State private var expandedBrokers: Set<BrokerIntegrationProvider> = []

    @Environment(\.themeColors) private var colors

    private let data: DataEnvironment

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

    init(data: DataEnvironment) {
        self.data = data
        let manage = ManageAccountsViewModel(
            trades: data.trades,
            session: data.session,
            detailCache: data.detailCache
        )
        _manageAccountsViewModel = State(initialValue: manage)
        _viewModel = State(
            initialValue: BrokerIntegrationsViewModel(
                broker: data.brokerIntegrations,
                manageAccounts: manage,
                session: data.session,
                detailCache: data.detailCache
            )
        )
    }

    var body: some View {
        List {
            if let oauthError = viewModel.oauthErrorMessage {
                Section {
                    Text(oauthError)
                        .experienceStyle(.footnote, color: colors.primaryText)
                    if !viewModel.isBrokerConnectionMutationActive {
                        Button("Retry Connect") {
                            viewModel.connectTradovate()
                        }
                    }
                }
            }

            if let message = viewModel.actionMessage {
                Section {
                    Text(message)
                        .experienceStyle(.footnote, color: viewModel.actionIsError ? colors.primaryText : colors.secondaryText)
                }
            }

            ForEach(visibleBrokerProviders, id: \.self) { provider in
                Section {
                    brokerCollapsibleSection(provider)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(colors.groupedBackground.ignoresSafeArea())
        .experienceNavigationTitle("Broker Integrations")
        .searchable(text: $brokerSearchText, prompt: "Search brokers")
        .background {
            BrokerIntegrationConnectionCoordinator(
                viewModel: viewModel,
                manageAccountsViewModel: manageAccountsViewModel,
                data: data,
                linkTarget: $linkTarget,
                createLinkTarget: $createLinkTarget,
                showsImportedTradesReview: true
            )
        }
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
        .onAppear {
            BrokerIntegrationsLoadPriorityGate.setScreenActive(true)
            manageAccountsViewModel.loadIfNeeded()
            Task { await viewModel.refreshAll() }
        }
        .onDisappear {
            BrokerIntegrationsLoadPriorityGate.setScreenActive(false)
        }
        .onChange(of: viewModel.tradovateConnections.count) { oldCount, newCount in
            guard newCount > 0, oldCount == 0 else { return }
            expandedBrokers.insert(.tradovate)
        }
        .onChange(of: viewModel.rithmicConnections.count) { oldCount, newCount in
            guard newCount > 0, oldCount == 0 else { return }
            expandedBrokers.insert(.rithmic)
        }
        .accessibilityIdentifier("settings.brokerIntegrations")
    }

    private var disconnectDialogTitle: String {
        switch disconnectTarget?.provider {
        case .rithmic: return "Disconnect Rithmic?"
        case .tradovate, .none: return "Disconnect Tradovate?"
        }
    }

    private var visibleBrokerProviders: [BrokerIntegrationProvider] {
        BrokerIntegrationsCatalog.filteredProviders(matching: brokerSearchText)
    }

    @ViewBuilder
    private func brokerCollapsibleSection(_ provider: BrokerIntegrationProvider) -> some View {
        let isExpanded = expandedBrokers.contains(provider)

        Button {
            ExperienceHaptics.play(.selection)
            if isExpanded {
                expandedBrokers.remove(provider)
            } else {
                expandedBrokers.insert(provider)
            }
        } label: {
            brokerSectionHeader(provider: provider, isExpanded: isExpanded)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("brokerIntegrations.section.\(provider.rawValue)")

        if isExpanded {
            switch provider {
            case .tradovate:
                tradovateSection
                Text("Connect your Tradovate login to discover accounts and import trades.")
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .listRowBackground(colors.groupedBackground)
            case .rithmic:
                rithmicSection
                rithmicExpandedFooter
            }
        }
    }

    private func brokerSectionHeader(provider: BrokerIntegrationProvider, isExpanded: Bool) -> some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                Text(BrokerIntegrationsCatalog.displayName(for: provider))
                    .experienceStyle(.body, color: colors.primaryText)
                Text(viewModel.collapsedSummary(for: provider))
                    .experienceStyle(.caption, color: colors.secondaryText)
            }
            Spacer(minLength: ExperienceSpacing.sm)
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(colors.tertiaryText)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .padding(.vertical, ExperienceSpacing.xxs)
    }

    @ViewBuilder
    private var rithmicExpandedFooter: some View {
        switch viewModel.rithmicConnectCapabilitiesPhase {
        case .loading:
            EmptyView()
        case .failed:
            EmptyView()
        case .loaded:
            if viewModel.isRithmicConnectUIAvailable {
                Text("Test environment only. Your Rithmic password is used only when you connect or import and is not saved by TradeTraxs.")
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .listRowBackground(colors.groupedBackground)
            } else {
                Text("Rithmic connection is not available on this server yet.")
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .listRowBackground(colors.groupedBackground)
            }
        }
    }

    @ViewBuilder
    private var tradovateSection: some View {
        switch viewModel.tradovateLoadPhase {
        case .loading where viewModel.tradovateConnections.isEmpty:
            HStack(spacing: ExperienceSpacing.sm) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading Tradovate…")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .failed(let message) where viewModel.tradovateConnections.isEmpty:
            VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                Text(message)
                    .experienceStyle(.footnote, color: colors.secondaryText)
                Button("Retry") {
                    Task { await viewModel.refreshAll() }
                }
                .font(.footnote)
                .buttonStyle(.borderless)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            EmptyView()
        }

        if viewModel.tradovateConnections.isEmpty,
           viewModel.tradovateLoadPhase != .loading
        {
            Button {
                viewModel.connectTradovate()
            } label: {
                Label("Connect Tradovate", systemImage: "link")
            }
            .disabled(viewModel.isBrokerConnectionMutationActive)
            .accessibilityIdentifier("brokerIntegrations.connectTradovate")
        }

        ForEach(viewModel.tradovateConnections) { connection in
            brokerConnectionHeader(connection)

            ForEach(viewModel.accounts(for: connection.id)) { account in
                brokerAccountRow(
                    provider: .tradovate,
                    connection: connection,
                    account: account
                )
            }

            if connection.isActiveForBrokerUI {
                if connection.status == .reconnectRequired {
                    brokerReconnectRequiredRow(
                        provider: .tradovate,
                        onReconnect: {
                            viewModel.connectTradovate(reconnectConnectionId: connection.id)
                        }
                    )
                }

                if connection.connected {
                    brokerRefreshAccountsRow(provider: .tradovate, connectionId: connection.id)
                }

                brokerDisconnectRow {
                    disconnectTarget = .tradovate(connection)
                }

                if connection.id == viewModel.tradovateConnections.last?.id {
                    VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                        Button {
                            viewModel.connectTradovate()
                        } label: {
                            Label("Connect Another Tradovate Login", systemImage: "plus.circle")
                        }
                        .disabled(viewModel.isBrokerConnectionMutationActive)

                        Text("TradeTraxs never stores your Tradovate password.")
                            .experienceStyle(.caption, color: colors.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private var rithmicSection: some View {
        switch viewModel.rithmicConnectionsLoadPhase {
        case .loading where viewModel.rithmicConnections.isEmpty:
            HStack(spacing: ExperienceSpacing.sm) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading Rithmic connections…")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .failed(let message) where viewModel.rithmicConnections.isEmpty:
            VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                Text(message)
                    .experienceStyle(.footnote, color: colors.secondaryText)
                Button("Retry") {
                    Task { await viewModel.refreshAll() }
                }
                .font(.footnote)
                .buttonStyle(.borderless)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            EmptyView()
        }

        rithmicConnectionRows

        switch viewModel.rithmicConnectCapabilitiesPhase {
        case .loading where viewModel.rithmicConnections.isEmpty:
            HStack(spacing: ExperienceSpacing.sm) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking Rithmic availability…")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .failed where viewModel.rithmicConnections.isEmpty:
            VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                Text("Couldn’t load Rithmic availability.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
                Button("Retry") {
                    Task { await viewModel.refreshAll() }
                }
                .font(.footnote)
                .buttonStyle(.borderless)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .loaded:
            if viewModel.isRithmicConnectUIAvailable {
                if viewModel.rithmicConnections.isEmpty {
                    Button {
                        viewModel.presentRithmicConnect()
                    } label: {
                        Label("Connect Rithmic", systemImage: "link")
                    }
                    .disabled(viewModel.isBrokerConnectionMutationActive)
                    .accessibilityIdentifier("brokerIntegrations.connectRithmic")
                }
            } else if viewModel.rithmicConnections.isEmpty {
                Text(rithmicUnavailableLabel)
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var rithmicConnectionRows: some View {
        ForEach(viewModel.rithmicConnections) { connection in
            brokerConnectionHeader(connection)

            ForEach(viewModel.accounts(for: connection.id)) { account in
                brokerAccountRow(
                    provider: .rithmic,
                    connection: connection,
                    account: account
                )
            }

            if connection.isActiveForBrokerUI {
                if connection.status == .reconnectRequired {
                    brokerReconnectRequiredRow(
                        provider: .rithmic,
                        onReconnect: {
                            viewModel.presentRithmicConnect(reconnectConnectionId: connection.id)
                        }
                    )
                }

                if connection.connected {
                    brokerRefreshAccountsRow(provider: .rithmic, connectionId: connection.id)
                }

                brokerDisconnectRow {
                    disconnectTarget = .rithmic(connection)
                }

                if connection.id == viewModel.rithmicConnections.last?.id {
                    VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                        Button {
                            viewModel.presentRithmicConnect()
                        } label: {
                            Label("Connect Another Rithmic Login", systemImage: "plus.circle")
                        }
                        .disabled(viewModel.isBrokerConnectionMutationActive)

                        Text("Your Rithmic password is sent once over HTTPS and is never stored on this device.")
                            .experienceStyle(.caption, color: colors.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
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

    @ViewBuilder
    private func brokerConnectionHeader(_ connection: TradovateConnectionSummary) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                    Text(connection.label)
                        .experienceStyle(.body, color: colors.primaryText)
                    Text(connectionSubtitle(connection))
                        .experienceStyle(.footnote, color: colors.secondaryText)
                }
                Spacer()
                if connection.connected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(colors.accent)
                        .accessibilityLabel("Connected")
                }
            }

            let accounts = viewModel.accounts(for: connection.id)
            if viewModel.isRefreshingAccounts.contains(connection.id) {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text("\(accounts.count) broker account(s)")
                    .experienceStyle(.caption, color: colors.tertiaryText)
            }
        }
        .padding(.vertical, ExperienceSpacing.xxs)
        .listRowInsets(
            EdgeInsets(
                top: ExperienceSpacing.xs,
                leading: ExperienceSpacing.md,
                bottom: ExperienceSpacing.xxs,
                trailing: ExperienceSpacing.md
            )
        )
    }

    private func brokerReconnectRequiredRow(
        provider: BrokerIntegrationProvider,
        onReconnect: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            Text(
                provider == .tradovate
                    ? "Tradovate authorization needs refreshing. Your linked accounts stay saved on TradeTraxs."
                    : "Rithmic authorization needs refreshing. Your linked accounts stay saved on TradeTraxs."
            )
            .experienceStyle(.caption, color: colors.secondaryText)
            Button("Reconnect", action: onReconnect)
                .font(.footnote)
                .buttonStyle(.borderless)
                .disabled(viewModel.isBrokerConnectionMutationActive)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func brokerRefreshAccountsRow(
        provider: BrokerIntegrationProvider,
        connectionId: String
    ) -> some View {
        Button {
            Task {
                await viewModel.loadAccounts(
                    provider: provider,
                    connectionId: connectionId,
                    forceRefresh: provider == .tradovate
                )
            }
        } label: {
            Text("Refresh Accounts")
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderless)
        .disabled(viewModel.isBrokerConnectionMutationActive)
    }

    private func brokerDisconnectRow(onDisconnect: @escaping () -> Void) -> some View {
        Button("Disconnect", role: .destructive, action: onDisconnect)
            .font(.footnote)
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(viewModel.isBrokerConnectionMutationActive)
    }

    @ViewBuilder
    private func brokerAccountRow(
        provider: BrokerIntegrationProvider,
        connection: TradovateConnectionSummary,
        account: BrokerIntegrationAccount
    ) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            Text(account.displayTitle)
                .experienceStyle(.subheadline, color: colors.primaryText)
            Text(BrokerIntegrationDisplay.brokerAccountNumberTail(account.externalAccountId, name: account.externalAccountName))
                .experienceStyle(.caption, color: colors.tertiaryText)
            if let linkedLine = BrokerIntegrationDisplay.linkedTradeTraxsLine(
                for: account,
                tradingAccounts: manageAccountsViewModel.accounts
            ) {
                Text(linkedLine)
                    .experienceStyle(.caption, color: colors.secondaryText)
            } else {
                Text(BrokerIntegrationDisplay.linkStatusLabel(for: account))
                    .experienceStyle(.caption, color: colors.secondaryText)
            }

            if account.hasTradetraxsMapping, connection.connected {
                Button {
                    Task {
                        await viewModel.importTrades(
                            provider: provider,
                            connectionId: connection.id,
                            mappingId: account.id
                        )
                    }
                } label: {
                    if viewModel.isImportingTrades(mappingId: account.id) {
                        Label("Importing…", systemImage: "arrow.triangle.2.circlepath")
                    } else {
                        Label("Import Trades", systemImage: "square.and.arrow.down")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.isImportingTrades(mappingId: account.id))
                .accessibilityIdentifier("brokerIntegrations.importTrades.\(account.id)")
            } else if !account.hasTradetraxsMapping, connection.connected {
                Button("Link Account") {
                    linkTarget = BrokerIntegrationLinkTarget(
                        provider: provider,
                        connectionId: connection.id,
                        account: account
                    )
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, ExperienceSpacing.xxs)
        .listRowInsets(
            EdgeInsets(
                top: ExperienceSpacing.xxs,
                leading: ExperienceSpacing.md,
                bottom: ExperienceSpacing.xxs,
                trailing: ExperienceSpacing.md
            )
        )
    }

    private func connectionSubtitle(_ connection: TradovateConnectionSummary) -> String {
        var parts: [String] = []
        if let name = connection.providerDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            parts.append(name)
        }
        if connection.status == .reconnectRequired {
            parts.append("Authorization refresh needed")
        } else if connection.connected {
            parts.append("Connected")
        } else {
            parts.append(connection.status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
        }
        if let env = connection.apiEnvironment {
            parts.append(env.uppercased())
        }
        return parts.joined(separator: " · ")
    }
}
