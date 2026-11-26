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
                        .experienceFloatingPanelBackground(
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                } else if viewModel.isConnectingRithmic, !viewModel.showsRithmicConnectSheet {
                    ProgressView("Connecting Rithmic…")
                        .padding(ExperienceSpacing.lg)
                        .experienceFloatingPanelBackground(
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
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
                .experienceSheetChrome()
            }
            .sheet(item: $createLinkTarget) { target in
                NavigationStack {
                    ManageAccountEditorView(
                        viewModel: manageAccountsViewModel,
                        mode: .create,
                        draft: target.draft,
                        data: data,
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
    let manageAccounts: [TradingAccount]
    let provider: BrokerIntegrationProvider
    let connectionId: String
    let brokerAccount: BrokerIntegrationAccount
    let onCreateNew: () -> Void

    @State private var selectedAccountID: TradingAccountID?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors

    private var eligibleLinkAccounts: [TradingAccount] {
        manageAccounts
    }

    private var brokerAccountNumberText: String {
        let trimmed = brokerAccount.externalAccountId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return brokerAccount.displayTitle
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SettingsIntroBlock(
                        title: "Link to TradeTraxs",
                        message: "Choose an account to link, or create a new one."
                    )
                    .experienceDashboardListRow()
                }

                Section {
                    brokerAccountCard
                        .padding(ExperienceSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .experienceGroupedPanel(cornerRadius: ExperienceRadius.md, prominence: .standard)
                        .listRowInsets(SettingsListLayout.groupedCardRowInsets)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                if !eligibleLinkAccounts.isEmpty {
                    Section("Link Existing") {
                        ForEach(eligibleLinkAccounts) { account in
                            linkableAccountRow(account)
                        }
                    }
                }

                Section {
                    Button {
                        dismiss()
                        onCreateNew()
                    } label: {
                        SettingsNavigationRow(
                            title: "Create New TradeTraxs Account",
                            subtitle: "Set up a new account linked to this broker.",
                            systemImage: "plus",
                            showsChevron: true
                        )
                    }
                    .buttonStyle(.experiencePlain)
                    .experienceDashboardListRow()
                    .accessibilityIdentifier("brokerIntegrations.linkAccount.createNew")
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
                    .disabled(selectedAccountID == nil)
                    .accessibilityIdentifier("brokerIntegrations.linkAccount.confirm")
                }
            }
        }
        .accessibilityIdentifier("brokerIntegrations.linkAccountSheet")
    }

    @ViewBuilder
    private var brokerAccountCard: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            SettingsLabeledField(title: "Broker Account") {
                Text(brokerAccountNumberText)
                    .experienceStyle(.body, color: colors.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if brokerAccount.displayTitle != brokerAccountNumberText {
                Text(brokerAccount.displayTitle)
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }
        }
    }

    private func linkableAccountRow(_ account: TradingAccount) -> some View {
        let isSelected = selectedAccountID == account.id
        return Button {
            ExperienceHaptics.play(.selection)
            selectedAccountID = account.id
        } label: {
            HStack(spacing: ExperienceSpacing.sm) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? colors.accent : colors.tertiaryText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                    Text(TradingAccountDisplay.title(for: account, audience: .owner))
                        .experienceStyle(.body, color: colors.primaryText)
                    Text(TradingAccountDisplay.ownerDropdownModeLabel(account.mode))
                        .experienceStyle(.footnote, color: colors.secondaryText)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.vertical, ExperienceSpacing.xxs)
        }
        .buttonStyle(.experiencePlain)
        .experienceDashboardListRow()
        .accessibilityIdentifier("brokerIntegrations.linkAccount.account.\(account.id.rawValue)")
    }
}
