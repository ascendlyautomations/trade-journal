import SwiftUI

/// Read-only withdrawal / payout history detail — optional post-as-achievement (no ledger mutation).
struct WithdrawalDetailView: View {
    let historyItemID: String
    let data: DataEnvironment
    let navigationCoordinator: NavigationCoordinator

    @Bindable private var withdrawalsHistory = WithdrawalsHistoryStore.shared
    @Bindable private var linkStore = WithdrawalAchievementLinkStore.shared
    @State private var accountsViewModel: ManageAccountsViewModel

    @Environment(\.themeColors) private var colors

    init(
        historyItemID: String,
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator
    ) {
        self.historyItemID = historyItemID
        self.data = data
        self.navigationCoordinator = navigationCoordinator
        _accountsViewModel = State(
            initialValue: ManageAccountsViewModel(
                trades: data.trades,
                session: data.session,
                detailCache: data.detailCache
            )
        )
    }

    private var historyItem: PayoutHistoryItem? {
        let items = PayoutHistorySupport.buildHistory(
            accounts: accountsViewModel.accounts,
            entriesByAccount: withdrawalsHistory.ledgerByAccount,
            cyclesByAccount: withdrawalsHistory.cyclesByAccount
        )
        return items.first { $0.id == historyItemID }
    }

    private var account: TradingAccount? {
        guard let item = historyItem else { return nil }
        return accountsViewModel.accounts.first { $0.id == item.accountID }
    }

    private var linkedAchievementID: AchievementID? {
        guard let item = historyItem else { return nil }
        return linkStore.linkedAchievementID(for: item)
    }

    private var screenTitle: String {
        guard let item = historyItem, let account else { return "Withdrawal" }
        return PayoutHistorySupport.isPropPayout(item, account: account) ? "Payout" : "Withdrawal"
    }

    var body: some View {
        Group {
            if let item = historyItem, let account {
                detailContent(item: item, account: account)
            } else {
                ExperienceEmptyState(
                    icon: .payouts,
                    title: "Withdrawal unavailable",
                    message: "This withdrawal could not be loaded. Pull to refresh from Withdrawals."
                )
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle(screenTitle)
        .toolbar(.hidden, for: .tabBar)
        .task {
            await hydrate()
        }
        .accessibilityIdentifier("withdrawals.detail.\(historyItemID)")
    }

    @ViewBuilder
    private func detailContent(item: PayoutHistoryItem, account: TradingAccount) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                headerBlock(item: item, account: account)
                if let notes = trimmedNotes(item.note) {
                    notesBlock(notes)
                }
                achievementActionBlock(item: item, account: account)
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.vertical, ExperienceSpacing.lg)
        }
    }

    private func headerBlock(item: PayoutHistoryItem, account: TradingAccount) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text(ProfileDisplay.formatMoney(item.amount))
                .font(.system(.largeTitle, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(colors.primaryText)

            Text(accountLine(account: account, item: item))
                .experienceStyle(.body, color: colors.secondaryText)

            Text(TradeDisplay.dateText(item.date))
                .experienceStyle(.subheadline, color: colors.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func notesBlock(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text("Notes")
                .experienceStyle(.headline, color: colors.primaryText)
            Text(notes)
                .experienceStyle(.body, color: colors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func achievementActionBlock(item: PayoutHistoryItem, account: TradingAccount) -> some View {
        if let achievementID = linkedAchievementID {
            Button {
                navigationCoordinator.pushHome(.achievementDetail(achievementID))
            } label: {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(colors.accent)
                    Text("Posted as Achievement")
                        .experienceStyle(.body, color: colors.primaryText)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(colors.tertiaryText)
                }
                .padding(ExperienceSpacing.md)
                .background(colors.fillSecondary.opacity(0.35), in: RoundedRectangle(
                    cornerRadius: ExperienceRadius.md,
                    style: .continuous
                ))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("withdrawals.detail.postedAchievement")
        } else if PropFirmPayoutCycleSupport.achievementPrefill(for: item, account: account) != nil {
            ExperienceButton(title: "Post as Achievement", kind: .primary) {
                postAsAchievement(item: item, account: account)
            }
            .accessibilityIdentifier("withdrawals.detail.postAsAchievement")
        }
    }

    private func postAsAchievement(item: PayoutHistoryItem, account: TradingAccount) {
        guard let prefill = PropFirmPayoutCycleSupport.achievementPrefill(for: item, account: account) else {
            return
        }
        CreateAchievementPrefillStore.shared.stage(prefill)
        navigationCoordinator.openComposeAchievement()
    }

    private func accountLine(account: TradingAccount, item: PayoutHistoryItem) -> String {
        let trimmedName = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let mode = TradingAccountDisplay.ownerDropdownModeLabel(account.mode)
        let kind = PayoutHistorySupport.isPropPayout(item, account: account) ? "Prop payout" : "Live withdrawal"
        if trimmedName.isEmpty {
            return "\(mode) · \(kind)"
        }
        return "\(trimmedName)\(TradingAccountDisplay.ownerDropdownSeparator)\(mode) · \(kind)"
    }

    private func trimmedNotes(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func hydrate() async {
        guard let userID = await data.session.currentUserID else { return }
        let profileID = ProfileID(userID.rawValue)
        withdrawalsHistory.bindProfile(profileID)
        withdrawalsHistory.hydrateFromSessionCaches(profileID: profileID)
        await accountsViewModel.ensureAccountsReadyForWithdrawals()
        await accountsViewModel.loadAllPayoutEntries()
        do {
            let rows = try await data.achievements.withdrawalAchievementLinks(for: profileID)
            linkStore.applyFetched(rows)
        } catch {
            WithdrawalsTrace.log("achievementLinksFetchFailed", detail: error.localizedDescription)
        }
    }
}
