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
    var linkPromptGate: BrokerIntegrationLinkPromptGate? = nil
    var showsImportedTradesReview: Bool

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .overlay {
                if viewModel.isConnecting {
                    ProgressView("Opening Tradovate…")
                        .padding(ExperienceSpacing.lg)
                        .experienceFloatingPanelBackground(
                            in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                        )
                } else if viewModel.isConnectingRithmic, !viewModel.showsRithmicConnectSheet {
                    ProgressView("Connecting Rithmic…")
                        .padding(ExperienceSpacing.lg)
                        .experienceFloatingPanelBackground(
                            in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                        )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .tradovateBrokerOAuthCompleted)) { note in
                let status = note.userInfo?[TradovateBrokerOAuthNotificationPayload.statusKey] as? String
                let reason = note.userInfo?[TradovateBrokerOAuthNotificationPayload.reasonKey] as? String
                Task { await viewModel.handleOAuthDeepLink(status: status, reason: reason) }
            }
            .sheet(item: $linkTarget, onDismiss: {
                guard let linkPromptGate else { return }
                linkPromptGate.handleLinkSheetDismissed(viewModel: viewModel)
            }) { target in
                BrokerLinkExistingAccountSheet(
                    viewModel: viewModel,
                    manageAccountsViewModel: manageAccountsViewModel,
                    provider: target.provider,
                    connectionId: target.connectionId,
                    brokerAccount: target.account,
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
            .sheet(item: $createLinkTarget) { target in
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
                            await viewModel.createAndLink(
                                provider: target.provider,
                                connectionId: target.connectionId,
                                brokerAccount: target.account,
                                draft: draft,
                                livePersonalDrawdown: liveDrawdown
                            )
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

    private var showsImportedTradesReviewBinding: Binding<Bool> {
        Binding(
            get: { showsImportedTradesReview && viewModel.showsReviewImportedTrades },
            set: { viewModel.showsReviewImportedTrades = $0 }
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
