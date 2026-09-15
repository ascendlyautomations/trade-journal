import SwiftUI

struct BrokerIntegrationsView: View {
    @State private var viewModel: BrokerIntegrationsViewModel
    @State private var manageAccountsViewModel: ManageAccountsViewModel
    @State private var linkTarget: BrokerLinkTarget?
    @State private var createLinkTarget: BrokerCreateLinkTarget?
    @State private var disconnectTarget: TradovateConnectionSummary?

    @Environment(\.themeColors) private var colors

    private let data: DataEnvironment

    private struct BrokerLinkTarget: Identifiable {
        let connectionId: String
        let account: BrokerIntegrationAccount
        var id: String { account.id }
    }

    private struct BrokerCreateLinkTarget: Identifiable {
        let connectionId: String
        let account: BrokerIntegrationAccount
        let draft: TradingAccountDraft
        var id: String { account.id }
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
                Text("Connect your Tradovate login to discover accounts and import trades. Credentials stay on TradeTraxs servers.")
            }

            Section {
                rithmicComingSoonRow
            } header: {
                Text("Rithmic")
            } footer: {
                Text("Production Rithmic connection will arrive after broker authorization is confirmed.")
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
            } else if viewModel.phase == .loading && viewModel.connections.isEmpty {
                ProgressView()
            }
        }
        .confirmationDialog(
            "Disconnect Tradovate?",
            isPresented: Binding(
                get: { disconnectTarget != nil },
                set: { if !$0 { disconnectTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                guard let target = disconnectTarget else { return }
                disconnectTarget = nil
                Task { await viewModel.disconnect(connectionId: target.id) }
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
                connectionId: target.connectionId,
                brokerAccount: target.account,
                onCreateNew: {
                    linkTarget = nil
                    createLinkTarget = BrokerCreateLinkTarget(
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
                            connectionId: target.connectionId,
                            brokerAccount: target.account,
                            draft: draft
                        )
                    }
                )
            }
            .experienceProtectedFormDismiss()
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

    @ViewBuilder
    private var tradovateSection: some View {
        if viewModel.connections.isEmpty, viewModel.phase != .loading {
            Button {
                viewModel.connectTradovate()
            } label: {
                Label("Connect Tradovate", systemImage: "link")
            }
            .disabled(viewModel.isBrokerConnectionMutationActive)
            .accessibilityIdentifier("brokerIntegrations.connectTradovate")
        }

        ForEach(viewModel.connections) { connection in
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                        Text(connection.label)
                            .experienceStyle(.body, color: colors.primaryText)
                        Text(tradovateConnectionSubtitle(connection))
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

                ForEach(accounts) { account in
                    brokerAccountRow(connectionId: connection.id, account: account)
                }

                if connection.isActiveForBrokerUI {
                    if connection.status == .reconnectRequired {
                        Button("Reconnect") {
                            viewModel.connectTradovate(reconnectConnectionId: connection.id)
                        }
                        .font(.footnote)
                        .disabled(viewModel.isBrokerConnectionMutationActive)
                    }

                    if connection.connected {
                        Button("Refresh Accounts") {
                            Task { await viewModel.loadAccounts(connectionId: connection.id, forceRefresh: true) }
                        }
                        .font(.footnote)
                        .disabled(viewModel.isBrokerConnectionMutationActive)

                        Button("Connect Another Account") {
                            viewModel.connectTradovate()
                        }
                        .font(.footnote)
                        .disabled(viewModel.isBrokerConnectionMutationActive)
                    }

                    Button("Disconnect", role: .destructive) {
                        disconnectTarget = connection
                    }
                    .font(.footnote)
                    .disabled(viewModel.isBrokerConnectionMutationActive)
                }
            }
            .padding(.vertical, ExperienceSpacing.xxs)
        }

        if !viewModel.connections.isEmpty {
            Button {
                viewModel.connectTradovate()
            } label: {
                Label("Connect Another Tradovate Login", systemImage: "plus.circle")
            }
            .disabled(viewModel.isBrokerConnectionMutationActive)
        }
    }

    @ViewBuilder
    private func brokerAccountRow(connectionId: String, account: BrokerIntegrationAccount) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            Text(account.displayTitle)
                .experienceStyle(.subheadline, color: colors.primaryText)
            Text(BrokerIntegrationDisplay.maskedAccountNumber(account.externalAccountId, name: account.externalAccountName))
                .experienceStyle(.caption, color: colors.tertiaryText)
            Text(BrokerIntegrationDisplay.linkStatusLabel(for: account))
                .experienceStyle(.caption, color: colors.secondaryText)

            if account.isLinked {
                Button {
                    Task { await viewModel.importTrades(connectionId: connectionId, mappingId: account.id) }
                } label: {
                    if viewModel.importingMappingIds.contains(account.id) {
                        Label("Importing…", systemImage: "arrow.triangle.2.circlepath")
                    } else {
                        Label("Import New Trades", systemImage: "square.and.arrow.down")
                    }
                }
                .disabled(viewModel.importingMappingIds.contains(account.id))
            } else {
                Button("Link Account") {
                    linkTarget = BrokerLinkTarget(connectionId: connectionId, account: account)
                }
            }
        }
        .padding(.vertical, ExperienceSpacing.xxs)
    }

    private var rithmicComingSoonRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                Text("Rithmic")
                    .experienceStyle(.body, color: colors.primaryText)
                Text("Coming Soon")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }
            Spacer()
            Image(systemName: "lock.fill")
                .foregroundStyle(colors.tertiaryText)
        }
    }

    private func tradovateConnectionSubtitle(_ connection: TradovateConnectionSummary) -> String {
        var parts: [String] = []
        if let name = connection.providerDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            parts.append(name)
        }
        if connection.connected {
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
