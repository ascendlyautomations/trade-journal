import SwiftUI

/// Linked broker accounts eligible for manual import (Tradovate, Rithmic, …).
struct BrokerLinkedImportReminderView: View {
    let data: DataEnvironment
    let accounts: [BrokerImportEligibilityTarget]
    let onClose: () -> Void

    @State private var importingIDs: Set<String> = []
    @State private var message: String?
    @State private var messageIsError = false
    @State private var reviewTradeIDs: [TradeID] = []
    @State private var showsReview = false
    @State private var tradingAccounts: [TradingAccount] = []

    @Environment(\.themeColors) private var colors

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                if let message {
                    Text(message)
                        .experienceStyle(.footnote, color: messageIsError ? colors.primaryText : colors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

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
        .sheet(isPresented: $showsReview) {
            BrokerImportedTradesReviewView(tradeIDs: reviewTradeIDs, data: data) {
                reviewTradeIDs = []
            }
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
                Task { await importTrades(for: account) }
            } label: {
                if importingIDs.contains(account.mappingId) {
                    Label("Importing…", systemImage: "arrow.triangle.2.circlepath")
                } else {
                    Label("Import Trades", systemImage: "square.and.arrow.down")
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(colors.accent)
            .padding(.top, ExperienceSpacing.xxs)
            .disabled(importingIDs.contains(account.mappingId))
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

    private func importTrades(for target: BrokerImportEligibilityTarget) async {
        importingIDs.insert(target.mappingId)
        defer { importingIDs.remove(target.mappingId) }
        do {
            let response: TradovateAccountSyncResponse
            switch target.provider {
            case .tradovate:
                response = try await data.brokerIntegrations.syncTradovateAccount(
                    connectionId: target.connectionId,
                    mappingId: target.mappingId
                )
            case .rithmic:
                response = try await data.brokerIntegrations.syncRithmicAccount(
                    connectionId: target.connectionId,
                    mappingId: target.mappingId
                )
            }
            let newIds = response.summary.newTradeIds
            if let userID = await data.session.currentUserID {
                TradeJournalMutationStore.shared.noteBulkImport(owner: ProfileID(userID.rawValue))
            }
            if response.summary.ok {
                if newIds.isEmpty {
                    present("Import finished — no new trades.", error: false)
                } else {
                    reviewTradeIDs = newIds.map { TradeID($0) }
                    showsReview = true
                    present("Imported \(newIds.count) trade(s).", error: false)
                }
            } else {
                present(response.summary.error ?? "Import did not complete.", error: true)
            }
        } catch {
            present(UserFacingError.message(for: error), error: true)
        }
    }

    private func present(_ text: String, error: Bool) {
        message = text
        messageIsError = error
    }
}
