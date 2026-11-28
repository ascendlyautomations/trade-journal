import SwiftUI

struct BrokerIntegrationLinkTarget: Identifiable {
    let provider: BrokerIntegrationProvider
    let connectionId: String
    let account: BrokerIntegrationAccount
    var id: String { account.id }
}

struct BrokerIntegrationCreateLinkTarget: Identifiable {
    let provider: BrokerIntegrationProvider
    let connectionId: String
    let account: BrokerIntegrationAccount
    let draft: TradingAccountDraft
    var id: String { account.id }
}

/// Shared Tradovate OAuth, Rithmic connect, and account link/create sheets for Settings and onboarding.
struct BrokerIntegrationConnectionCoordinator: View {
    @Bindable var viewModel: BrokerIntegrationsViewModel
    @Bindable var manageAccountsViewModel: ManageAccountsViewModel
    let data: DataEnvironment
    @Binding var linkTarget: BrokerIntegrationLinkTarget?
    @Binding var createLinkTarget: BrokerIntegrationCreateLinkTarget?
    @Binding var pendingLinkSetupTarget: BrokerTradovatePendingLinkSetupTarget?
    @Binding var pendingLinkCreateTarget: BrokerTradovatePendingLinkSetupTarget?
    @Binding var pendingConfirmTarget: BrokerPendingTradovateLinkConfirmTarget?
    var linkPromptGate: BrokerIntegrationLinkPromptGate? = nil
    var showsImportedTradesReview: Bool

    init(
        viewModel: BrokerIntegrationsViewModel,
        manageAccountsViewModel: ManageAccountsViewModel,
        data: DataEnvironment,
        linkTarget: Binding<BrokerIntegrationLinkTarget?>,
        createLinkTarget: Binding<BrokerIntegrationCreateLinkTarget?>,
        pendingLinkSetupTarget: Binding<BrokerTradovatePendingLinkSetupTarget?> = .constant(nil),
        pendingLinkCreateTarget: Binding<BrokerTradovatePendingLinkSetupTarget?> = .constant(nil),
        pendingConfirmTarget: Binding<BrokerPendingTradovateLinkConfirmTarget?> = .constant(nil),
        linkPromptGate: BrokerIntegrationLinkPromptGate? = nil,
        showsImportedTradesReview: Bool
    ) {
        self.viewModel = viewModel
        self.manageAccountsViewModel = manageAccountsViewModel
        self.data = data
        _linkTarget = linkTarget
        _createLinkTarget = createLinkTarget
        _pendingLinkSetupTarget = pendingLinkSetupTarget
        _pendingLinkCreateTarget = pendingLinkCreateTarget
        _pendingConfirmTarget = pendingConfirmTarget
        self.linkPromptGate = linkPromptGate
        self.showsImportedTradesReview = showsImportedTradesReview
    }

    var body: some View {
        connectMutationLoadingOverlay
            .onReceive(NotificationCenter.default.publisher(for: .tradovateBrokerOAuthCompleted)) { note in
                let status = note.userInfo?[TradovateBrokerOAuthNotificationPayload.statusKey] as? String
                let reason = note.userInfo?[TradovateBrokerOAuthNotificationPayload.reasonKey] as? String
                Task { await viewModel.handleOAuthDeepLink(status: status, reason: reason) }
            }
            .sheet(item: $linkTarget, onDismiss: {
                guard let linkPromptGate else { return }
                linkPromptGate.handleLinkSheetDismissed(viewModel: viewModel)
                continueAutoLinkSequenceIfNeeded()
            }) { target in
                BrokerLinkExistingAccountSheet(
                    viewModel: viewModel,
                    manageAccountsViewModel: manageAccountsViewModel,
                    provider: target.provider,
                    connectionId: target.connectionId,
                    brokerAccount: target.account,
                    linkPromptGate: linkPromptGate,
                    onCreateNew: {
                        linkTarget = nil
                        createLinkTarget = BrokerIntegrationCreateLinkTarget(
                            provider: target.provider,
                            connectionId: target.connectionId,
                            account: target.account,
                            draft: viewModel.draftForCreate(from: target.account)
                        )
                    }
                )
                .experienceSheetChrome()
            }
            .sheet(item: $pendingLinkSetupTarget) { target in
                BrokerTradovatePendingLinkSetupSheet(
                    viewModel: viewModel,
                    manageAccountsViewModel: manageAccountsViewModel,
                    connectionId: target.connectionId,
                    onCreateNew: {
                        pendingLinkSetupTarget = nil
                        pendingLinkCreateTarget = target
                    }
                )
                .experienceSheetChrome()
            }
            .sheet(item: $pendingLinkCreateTarget) { target in
                NavigationStack {
                    ManageAccountEditorView(
                        viewModel: manageAccountsViewModel,
                        mode: .create,
                        draft: manageAccountsViewModel.emptyDraft(),
                        data: data,
                        onCreateSubmit: { draft, liveDrawdown in
                            let saved = await viewModel.createTradovatePendingLink(
                                connectionId: target.connectionId,
                                draft: draft,
                                livePersonalDrawdown: liveDrawdown
                            )
                            if saved {
                                pendingLinkCreateTarget = nil
                            }
                            return saved
                        }
                    )
                }
                .experienceProtectedFormDismiss()
            }
            .sheet(item: $pendingConfirmTarget, onDismiss: {
                guard let linkPromptGate else { return }
                linkPromptGate.handleLinkSheetDismissed(viewModel: viewModel)
                continueAutoLinkSequenceIfNeeded()
            }) { target in
                BrokerPendingTradovateLinkConfirmSheet(
                    viewModel: viewModel,
                    target: target,
                    linkPromptGate: linkPromptGate
                )
                .experienceSheetChrome()
            }
            .sheet(item: $createLinkTarget, onDismiss: {
                continueAutoLinkSequenceIfNeeded()
            }) { target in
                NavigationStack {
                    ManageAccountEditorView(
                        viewModel: manageAccountsViewModel,
                        mode: .create,
                        draft: target.draft,
                        data: data,
                        brokerLinkContext: BrokerAccountLinkContext(
                            provider: target.provider,
                            account: target.account
                        ),
                        onCreateSubmit: { draft, liveDrawdown in
                            let linked = await viewModel.createAndLink(
                                provider: target.provider,
                                connectionId: target.connectionId,
                                brokerAccount: target.account,
                                draft: draft,
                                livePersonalDrawdown: liveDrawdown
                            )
                            if linked {
                                linkPromptGate?.noteSuccessfulLink(mappingID: target.account.id)
                            }
                            return linked
                        }
                    )
                }
                .experienceProtectedFormDismiss()
            }
            .sheet(isPresented: $viewModel.showsRithmicConnectSheet, onDismiss: {
                viewModel.clearRithmicSheetStateOnDismiss()
            }) {
                RithmicConnectSheet(
                    mode: viewModel.rithmicConnectSheetMode,
                    isBusy: viewModel.isConnectingRithmic,
                    systemChoices: viewModel.rithmicSystemChoices,
                    prefilledUsername: viewModel.rithmicSheetPrefilledUsername,
                    prefilledSystemName: viewModel.rithmicSheetPrefilledSystemName,
                    locksUsername: viewModel.rithmicSheetLocksUsername,
                    onSubmit: { username, password, systemName in
                        await viewModel.submitRithmicConnect(
                            username: username,
                            password: password,
                            systemName: systemName
                        )
                    }
                )
            }
            .sheet(isPresented: showsImportedTradesReviewBinding) {
                BrokerImportedTradesReviewView(
                    tradeIDs: viewModel.pendingReviewTradeIDs,
                    data: data
                ) {
                    viewModel.pendingReviewTradeIDs = []
                }
            }
            .sheet(isPresented: $viewModel.showsTradovateImportPreview) {
                if let pending = viewModel.pendingTradovateImportPreview {
                    BrokerTradovateImportPreviewView(
                        trades: pending.trades,
                        isConfirming: viewModel.isConfirmingTradovateImport,
                        onConfirm: {
                            await viewModel.confirmTradovateImportFromPreview()
                        },
                        onCancel: {
                            viewModel.cancelTradovateImportPreview()
                        }
                    )
                }
            }
            .confirmationDialog(
                "Connect Tradovate",
                isPresented: $viewModel.showsTradovateEnvironmentPicker,
                titleVisibility: .visible
            ) {
                Button("Live (production)") {
                    viewModel.connectTradovateWithEnvironment("live")
                }
                Button("Demo (simulation)") {
                    viewModel.connectTradovateWithEnvironment("demo")
                }
                Button("Cancel", role: .cancel) {
                    viewModel.showsTradovateEnvironmentPicker = false
                }
            } message: {
                Text(
                    "Choose the Tradovate environment that matches the account you sign in with. Live and Demo use separate API data."
                )
            }
    }

    @ViewBuilder
    private var connectMutationLoadingOverlay: some View {
        if viewModel.isConnecting {
            brokerConnectLoadingPanel(
                label: "Opening Tradovate",
                message: "Opening Tradovate…"
            )
        } else if viewModel.isConnectingRithmic, !viewModel.showsRithmicConnectSheet {
            brokerConnectLoadingPanel(
                label: "Connecting Rithmic",
                message: "Connecting Rithmic…"
            )
        }
    }

    private func brokerConnectLoadingPanel(label: String, message: String) -> some View {
        ZStack {
            ExperienceLoadingSpinner(label: label, message: message)
                .padding(ExperienceSpacing.lg)
                .experienceFloatingPanelBackground(
                    in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("brokerIntegrations.connectMutationLoading")
    }

    private var showsImportedTradesReviewBinding: Binding<Bool> {
        Binding(
            get: { showsImportedTradesReview && viewModel.showsReviewImportedTrades },
            set: { viewModel.showsReviewImportedTrades = $0 }
        )
    }

    private func continueAutoLinkSequenceIfNeeded() {
        guard let linkPromptGate, linkPromptGate.autoLinkSequenceActive else { return }
        BrokerIntegrationAutoLinkPrompt.schedule(
            viewModel: viewModel,
            gate: linkPromptGate,
            linkTarget: $linkTarget,
            createLinkTarget: $createLinkTarget
        )
    }
}

// MARK: - Link existing sheet

struct BrokerLinkExistingAccountSheet: View {
    let viewModel: BrokerIntegrationsViewModel
    @Bindable var manageAccountsViewModel: ManageAccountsViewModel
    let provider: BrokerIntegrationProvider
    let connectionId: String
    let brokerAccount: BrokerIntegrationAccount
    var linkPromptGate: BrokerIntegrationLinkPromptGate? = nil
    let onCreateNew: () -> Void

    @State private var selectedAccountID: TradingAccountID?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors

    private var eligiblePresentation: BrokerLinkEligibleAccountsPresentation {
        BrokerLinkEligibleAccountsPresentation.resolve(
            isLoading: manageAccountsViewModel.isLoading,
            errorMessage: manageAccountsViewModel.errorMessage,
            accounts: manageAccountsViewModel.accounts
        )
    }

    private var canConfirmLink: Bool {
        if case .ready = eligiblePresentation {
            return selectedAccountID != nil
        }
        return false
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    BrokerDiscoveredAccountSummaryCard(provider: provider, account: brokerAccount)
                        .brokerIntegrationsCardListRow()
                }

                Section {
                    Text("Link an existing TradeTraxs account")
                        .experienceStyle(.subheadline, color: colors.primaryText)
                        .listRowSeparator(.hidden)
                    BrokerLinkExistingAccountsSection(
                        presentation: eligiblePresentation,
                        accounts: manageAccountsViewModel.accounts,
                        selectedAccountID: $selectedAccountID,
                        onRetryLoad: {
                            Task { await manageAccountsViewModel.refresh() }
                        }
                    )
                    .experienceDashboardListRow()
                }

                Section {
                    ExperienceButton(
                        title: "Create New TradeTraxs Account",
                        icon: .create,
                        kind: .secondary,
                        accessibilityIdentifier: "brokerIntegrations.linkAccount.createNew"
                    ) {
                        dismiss()
                        onCreateNew()
                    }
                    .experienceDashboardListRow()
                    .listRowInsets(
                        EdgeInsets(
                            top: ExperienceSpacing.xs,
                            leading: ExperienceSpacing.md,
                            bottom: ExperienceSpacing.md,
                            trailing: ExperienceSpacing.md
                        )
                    )
                }
            }
            .experienceInsetGroupedListStyle(pageBackground: false)
            .listRowSeparatorTint(colors.separator)
            .listSectionSpacing(ExperienceSpacing.xs)
            .experienceNavigationTitle("Link Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("brokerIntegrations.linkAccount.cancel")
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
                                linkPromptGate?.noteSuccessfulLink(mappingID: brokerAccount.id)
                                dismiss()
                            }
                        }
                    }
                    .disabled(!canConfirmLink)
                    .accessibilityIdentifier("brokerIntegrations.linkAccount.confirm")
                }
            }
            .task {
                manageAccountsViewModel.loadIfNeeded()
                if manageAccountsViewModel.accounts.isEmpty {
                    await manageAccountsViewModel.refresh()
                }
            }
        }
        .accessibilityIdentifier("brokerIntegrations.linkAccountSheet")
    }
}
