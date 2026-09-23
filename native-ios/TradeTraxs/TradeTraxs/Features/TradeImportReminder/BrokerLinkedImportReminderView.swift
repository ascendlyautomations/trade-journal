import SwiftUI

/// Linked broker accounts eligible for manual import (Tradovate, Rithmic, …).
struct BrokerLinkedImportReminderView: View {
    let data: DataEnvironment
    let accounts: [BrokerImportEligibilityTarget]
    let onClose: () -> Void

    @State private var importFlow = BrokerImportFlowModel()
    @State private var tradingAccounts: [TradingAccount] = []
    @State private var reviewTradeIDs: [TradeID] = []
    @State private var showsReview = false
    @State private var singleEditTradeID: TradeID?
    @State private var showsSingleEdit = false
    @State private var rithmicReauthTarget: BrokerImportEligibilityTarget?
    @State private var showsRithmicReauth = false
    @State private var isRithmicReauthBusy = false
    @State private var rithmicReauthUsername: String?

    @Environment(\.themeColors) private var colors

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                Text("Choose a linked broker account to import new trades.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Linked Broker Accounts")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(colors.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.4)
                    .padding(.top, ExperienceSpacing.xxs)
                    .accessibilityAddTraits(.isHeader)

                VStack(spacing: ExperienceSpacing.sm) {
                    ForEach(accounts) { account in
                        accountCard(account)
                    }
                }
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.top, ExperienceSpacing.xs)
            .padding(.bottom, ExperienceSpacing.md)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(colors.groupedBackground.ignoresSafeArea())
        .experienceNavigationTitle("Broker Import")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", action: onClose)
            }
        }
        .task {
            await loadTradingAccountsIfNeeded()
        }
        .fullScreenCover(isPresented: $importFlow.isPresented) {
            BrokerImportProgressView(
                model: importFlow,
                data: data,
                onReviewImportedTrades: { ids in
                    reviewTradeIDs = ids
                    showsReview = true
                },
                onEditSingleImportedTrade: { id in
                    singleEditTradeID = id
                    showsSingleEdit = true
                },
                onClose: {}
            )
        }
        .sheet(isPresented: $showsReview) {
            BrokerImportedTradesReviewView(tradeIDs: reviewTradeIDs, data: data) {
                reviewTradeIDs = []
            }
        }
        .sheet(isPresented: $showsSingleEdit, onDismiss: { singleEditTradeID = nil }) {
            if let id = singleEditTradeID {
                NavigationStack {
                    AddTradeView(
                        data: data,
                        mode: .edit(id),
                        embeddedInTradeEntryHub: false,
                        onDismiss: { showsSingleEdit = false }
                    )
                    .experienceNavigationTitle("Imported Trade")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showsSingleEdit = false }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showsRithmicReauth, onDismiss: {
            rithmicReauthTarget = nil
            rithmicReauthUsername = nil
        }) {
            RithmicConnectSheet(
                mode: .importTrades,
                isBusy: isRithmicReauthBusy,
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
        .accessibilityIdentifier("tradeImportReminder.brokerImport")
    }

    private func accountCard(_ account: BrokerImportEligibilityTarget) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            Text(account.brokerAccountLabel)
                .experienceStyle(.subheadline, color: colors.primaryText)
                .fontWeight(.semibold)
                .lineLimit(1)

            Text(
                BrokerIntegrationDisplay.brokerImportMetadataLine(
                    provider: account.provider,
                    tradetraxsAccountName: account.tradetraxsAccountName,
                    tradingAccounts: tradingAccounts
                )
            )
            .experienceStyle(.footnote, color: colors.secondaryText)
            .lineLimit(2)

            Button {
                importFlow.startImport(target: account, data: data)
            } label: {
                Label("Import Trades", systemImage: "square.and.arrow.down")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(colors.accent)
            .padding(.top, ExperienceSpacing.xxs)
            .disabled(importFlow.isPresented)
            .accessibilityIdentifier("brokerImport.importTrades.\(account.mappingId)")
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.vertical, ExperienceSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.fillSecondary.opacity(0.35), in: RoundedRectangle(
            cornerRadius: ExperienceRadius.md,
            style: .continuous
        ))
        .overlay {
            RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                .stroke(colors.border.opacity(0.35), lineWidth: ExperienceBorder.hairline)
        }
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
