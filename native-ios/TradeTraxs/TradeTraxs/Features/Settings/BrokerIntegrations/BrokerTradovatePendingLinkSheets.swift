import SwiftUI

struct BrokerTradovatePendingLinkSetupTarget: Identifiable {
    let connectionId: String
    var id: String { connectionId }
}

struct BrokerPendingTradovateLinkConfirmTarget: Identifiable {
    let connectionId: String
    let brokerAccount: BrokerIntegrationAccount
    let pending: BrokerConnectionPendingLinkPreference
    var id: String { "\(connectionId)-\(brokerAccount.id)" }
}

/// Choose or create a TradeTraxs account to link once Tradovate exposes broker accounts.
struct BrokerTradovatePendingLinkSetupSheet: View {
    @Bindable var viewModel: BrokerIntegrationsViewModel
    @Bindable var manageAccountsViewModel: ManageAccountsViewModel
    let connectionId: String
    let onCreateNew: () -> Void

    @State private var selectedAccountID: TradingAccountID?
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors

    private var eligiblePresentation: BrokerLinkEligibleAccountsPresentation {
        BrokerLinkEligibleAccountsPresentation.resolve(
            isLoading: manageAccountsViewModel.isLoading,
            errorMessage: manageAccountsViewModel.errorMessage,
            accounts: manageAccountsViewModel.accounts
        )
    }

    private var canConfirm: Bool {
        if case .ready = eligiblePresentation {
            return selectedAccountID != nil
        }
        return false
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(
                        "Tradovate is connected, but no trading accounts are available yet. Choose a TradeTraxs account now and we will link it when Tradovate accounts appear."
                    )
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .listRowSeparator(.hidden)
                }

                Section {
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
                        accessibilityIdentifier: "brokerIntegrations.pendingLink.createNew"
                    ) {
                        dismiss()
                        onCreateNew()
                    }
                    .experienceDashboardListRow()
                }
            }
            .experienceInsetGroupedListStyle(pageBackground: false)
            .experienceNavigationTitle("Reserve Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard !isSaving, let id = selectedAccountID else { return }
                        isSaving = true
                        Task {
                            defer { isSaving = false }
                            if await viewModel.setTradovatePendingLink(
                                connectionId: connectionId,
                                tradetraxsAccountId: id
                            ) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(!canConfirm || isSaving)
                }
            }
            .task {
                manageAccountsViewModel.loadIfNeeded()
                if manageAccountsViewModel.accounts.isEmpty {
                    await manageAccountsViewModel.refresh()
                }
            }
        }
    }
}

/// Confirms linking a newly discovered broker account to a previously reserved TradeTraxs account.
struct BrokerPendingTradovateLinkConfirmSheet: View {
    let viewModel: BrokerIntegrationsViewModel
    let target: BrokerPendingTradovateLinkConfirmTarget
    var linkPromptGate: BrokerIntegrationLinkPromptGate? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors

    var body: some View {
        NavigationStack {
            List {
                Section {
                    BrokerDiscoveredAccountSummaryCard(
                        provider: .tradovate,
                        account: target.brokerAccount
                    )
                    .brokerIntegrationsCardListRow()
                }

                Section {
                    Text("Link to your reserved TradeTraxs account")
                        .experienceStyle(.subheadline, color: colors.primaryText)
                    Text(target.pending.tradetraxsAccountName ?? "TradeTraxs Account")
                        .font(ExperienceTypography.headline)
                        .foregroundStyle(colors.accent)
                }
            }
            .experienceInsetGroupedListStyle(pageBackground: false)
            .experienceNavigationTitle("Confirm Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Link") {
                        Task {
                            let linked = await viewModel.confirmPendingTradovateLink(
                                connectionId: target.connectionId,
                                brokerAccount: target.brokerAccount,
                                tradetraxsAccountId: TradingAccountID(target.pending.tradetraxsAccountId)
                            )
                            if linked {
                                linkPromptGate?.noteSuccessfulLink(mappingID: target.brokerAccount.id)
                                dismiss()
                            }
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("brokerIntegrations.pendingLinkConfirmSheet")
    }
}

enum BrokerTradovateNoAccountsCopy {
    static let connectedStatus = "Connected — No trading accounts found yet."
}