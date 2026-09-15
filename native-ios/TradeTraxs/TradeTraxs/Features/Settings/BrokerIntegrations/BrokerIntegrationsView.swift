import SwiftUI

struct BrokerIntegrationsView: View {
    @State private var viewModel: BrokerIntegrationsViewModel
    @State private var manageAccountsViewModel: ManageAccountsViewModel
    @State private var linkTarget: BrokerLinkTarget?
    @State private var createLinkTarget: BrokerCreateLinkTarget?
    @State private var disconnectTarget: BrokerDisconnectTarget?

    @Environment(\.themeColors) private var colors

    private let data: DataEnvironment

    private struct BrokerLinkTarget: Identifiable {
        let provider: BrokerIntegrationProvider
        let connectionId: String
        let account: BrokerIntegrationAccount
        var id: String { account.id }
    }

    private struct BrokerCreateLinkTarget: Identifiable {
        let provider: BrokerIntegrationProvider
        let connectionId: String
        let account: BrokerIntegrationAccount
        let draft: TradingAccountDraft
        var id: String { account.id }
    }

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

            if case .failed(let error) = viewModel.phase {
                Section {
                    SettingsInlineError(message: error) {
                        Task { await viewModel.refreshAll() }
                    }
                }
            }

            Section {
                tradovateSection
            } header: {
                Text("Tradovate")
            } footer: {
                Text("Connect your Tradovate login to discover accounts and import trades.")
            }

            Section {
                rithmicSection
            } header: {
                Text("Rithmic")
            } footer: {
                rithmicSectionFooter
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(colors.groupedBackground.ignoresSafeArea())
        .experienceNavigationTitle("Broker Integrations")
        .overlay {
            if viewModel.isConnecting {
                ProgressView("Opening Tradovate…")
                    .padding(ExperienceSpacing.lg)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            } else if viewModel.isConnectingRithmic {
                ProgressView("Connecting Rithmic…")
                    .padding(ExperienceSpacing.lg)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            } else if viewModel.phase == .loading,
                      viewModel.tradovateConnections.isEmpty,
                      viewModel.rithmicConnections.isEmpty
            {
                ProgressView()
            }
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
            manageAccountsViewModel.loadIfNeeded()
            Task { await viewModel.refreshAll() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tradovateBrokerOAuthCompleted)) { note in
            let status = note.userInfo?[TradovateBrokerOAuthNotificationPayload.statusKey] as? String
            let reason = note.userInfo?[TradovateBrokerOAuthNotificationPayload.reasonKey] as? String
            Task { await viewModel.handleOAuthDeepLink(status: status, reason: reason) }
        }
        .sheet(item: $linkTarget) { target in
            BrokerLinkExistingAccountSheet(
                viewModel: viewModel,
                manageAccounts: manageAccountsViewModel.accounts,
                provider: target.provider,
                connectionId: target.connectionId,
                brokerAccount: target.account,
                onCreateNew: {
                    linkTarget = nil
                    createLinkTarget = BrokerCreateLinkTarget(
                        provider: target.provider,
                        connectionId: target.connectionId,
                        account: target.account,
                        draft: viewModel.draftForCreate(from: target.account)
                    )
                }
            )
        }
        .sheet(item: $createLinkTarget) { target in
            NavigationStack {
                ManageAccountEditorView(
                    viewModel: manageAccountsViewModel,
                    mode: .create,
                    draft: target.draft,
                    data: data,
                    onCreateSubmit: { draft in
                        await viewModel.createAndLink(
                            provider: target.provider,
                            connectionId: target.connectionId,
                            brokerAccount: target.account,
                            draft: draft
                        )
                    }
                )
            }
            .experienceProtectedFormDismiss()
        }
        .sheet(isPresented: $viewModel.showsRithmicConnectSheet) {
            RithmicConnectSheet(
                isBusy: viewModel.isConnectingRithmic,
                systemChoices: viewModel.rithmicSystemChoices,
                reconnectTitle: viewModel.rithmicReconnectConnectionId == nil
                    ? "Your Rithmic password is sent once over HTTPS and is never stored on this device."
                    : "Reconnect with your Rithmic credentials.",
                onSubmit: { username, password, systemName in
                    await viewModel.submitRithmicConnect(
                        username: username,
                        password: password,
                        systemName: systemName
                    )
                }
            )
        }
        .sheet(isPresented: $viewModel.showsReviewImportedTrades) {
            BrokerImportedTradesReviewView(
                tradeIDs: viewModel.pendingReviewTradeIDs,
                data: data
            ) {
                viewModel.pendingReviewTradeIDs = []
            }
        }
        .accessibilityIdentifier("settings.brokerIntegrations")
    }

    private var disconnectDialogTitle: String {
        switch disconnectTarget?.provider {
        case .rithmic: return "Disconnect Rithmic?"
        case .tradovate, .none: return "Disconnect Tradovate?"
        }
    }

    @ViewBuilder
    private var rithmicSectionFooter: some View {
        if viewModel.isRithmicConnectUIAvailable {
            Text("Test environment only. Rithmic credentials are verified on TradeTraxs servers and encrypted there — not on this device.")
        } else {
            Text("Rithmic connection is not available on this server yet.")
        }
    }

    @ViewBuilder
    private var tradovateSection: some View {
        if viewModel.tradovateConnections.isEmpty, viewModel.phase != .loading {
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
        if viewModel.isRithmicConnectUIAvailable {
            if viewModel.rithmicConnections.isEmpty, viewModel.phase != .loading {
                Button {
                    viewModel.presentRithmicConnect()
                } label: {
                    Label("Connect Rithmic", systemImage: "link")
                }
                .disabled(viewModel.isBrokerConnectionMutationActive)
                .accessibilityIdentifier("brokerIntegrations.connectRithmic")
            }

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
                }
            }

            if !viewModel.rithmicConnections.isEmpty {
                brokerSectionDividerRow

                Button {
                    viewModel.presentRithmicConnect()
                } label: {
                    Label("Connect Another Rithmic Login", systemImage: "plus.circle")
                }
                .disabled(viewModel.isBrokerConnectionMutationActive)
            }
        } else {
            HStack {
                VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                    Text("Unavailable")
                        .experienceStyle(.body, color: colors.primaryText)
                    Text(rithmicUnavailableLabel)
                        .experienceStyle(.footnote, color: colors.secondaryText)
                }
                Spacer()
                Image(systemName: "lock.fill")
                    .foregroundStyle(colors.tertiaryText)
            }
        }
    }

    private var rithmicUnavailableLabel: String {
        guard let caps = viewModel.rithmicConnectCapabilities else {
            return "Could not load Rithmic availability."
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

    private var brokerSectionDividerRow: some View {
        Color.clear
            .frame(height: 1)
            .listRowInsets(EdgeInsets())
            .listRowBackground(colors.groupedBackground)
            .accessibilityHidden(true)
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
                    linkTarget = BrokerLinkTarget(
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

// MARK: - Link existing sheet

private struct BrokerLinkExistingAccountSheet: View {
    let viewModel: BrokerIntegrationsViewModel
    let manageAccounts: [TradingAccount]
    let provider: BrokerIntegrationProvider
    let connectionId: String
    let brokerAccount: BrokerIntegrationAccount
    let onCreateNew: () -> Void

    @State private var selectedAccountID: TradingAccountID?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(brokerAccount.displayTitle)
                        .experienceStyle(.body, color: colors.primaryText)
                    Text("Choose a TradeTraxs account to link, or create a new one.")
                        .experienceStyle(.footnote, color: colors.secondaryText)
                }

                Section("Link Existing") {
                    ForEach(manageAccounts) { account in
                        Button {
                            selectedAccountID = account.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(account.name)
                                    Text(account.category.rawValue.capitalized)
                                        .experienceStyle(.caption, color: colors.secondaryText)
                                }
                                Spacer()
                                if selectedAccountID == account.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(colors.accent)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    Button("Create New Trading Account") {
                        dismiss()
                        onCreateNew()
                    }
                }
            }
            .experienceNavigationTitle("Link Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Link") {
                        Task {
                            guard let id = selectedAccountID else { return }
                            if await viewModel.linkExisting(
                                provider: provider,
                                connectionId: connectionId,
                                brokerAccount: brokerAccount,
                                tradetraxsAccountId: id
                            ) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(selectedAccountID == nil)
                }
            }
        }
    }
}
