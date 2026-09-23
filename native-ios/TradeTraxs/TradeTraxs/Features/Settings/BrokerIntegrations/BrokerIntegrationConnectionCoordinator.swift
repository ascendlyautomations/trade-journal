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
    var showsImportedTradesReview: Bool

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .overlay {
                if viewModel.isConnecting {
                    ProgressView("Opening Tradovate…")
                        .padding(ExperienceSpacing.lg)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                } else if viewModel.isConnectingRithmic, !viewModel.showsRithmicConnectSheet {
                    ProgressView("Connecting Rithmic…")
                        .padding(ExperienceSpacing.lg)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
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
                        createLinkTarget = BrokerIntegrationCreateLinkTarget(
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
                    Button("Create New TradeTraxs Account") {
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
