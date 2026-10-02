import SwiftUI

/// Read-only withdrawal / payout history detail — optional post-as-achievement (no ledger mutation).
struct WithdrawalDetailView: View {
    let historyItemID: String
    let data: DataEnvironment
    let navigationCoordinator: NavigationCoordinator

    @Bindable private var withdrawalsHistory = WithdrawalsHistoryStore.shared
    @Bindable private var linkStore = WithdrawalAchievementLinkStore.shared
    @State private var accountsViewModel: ManageAccountsViewModel
    @State private var didFinishHydrate = false
    @State private var showsEditor = false
    @State private var editorDraft = AccountPayoutEntryDraft(amountDigits: "", payoutDate: .now, note: "")
    @State private var confirmsDelete = false
    @State private var imageOwnerID: String?

    @Environment(\.themeColors) private var colors
    @Environment(\.dismiss) private var dismiss

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
            } else if !didFinishHydrate {
                ProgressView("Loading withdrawal…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .toolbar {
            if historyItem?.isEditable == true {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { beginEdit() }
                        .accessibilityIdentifier("withdrawals.detail.edit")
                }
            }
        }
        .onAppear {
            accountsViewModel.seedWithdrawalsAccountsFromSessionCache()
        }
        .task {
            await hydrate()
        }
        .sheet(isPresented: $showsEditor) {
            if let item = historyItem, let entryID = item.ledgerEntryID {
                AccountPayoutEditorSheet(
                    viewModel: accountsViewModel,
                    accountID: item.accountID,
                    editingEntryID: entryID,
                    draft: $editorDraft,
                    isPresented: $showsEditor,
                    copy: .payoutHistory,
                    imageStorage: data.objectStorage,
                    imageOwnerID: imageOwnerID
                )
            }
        }
        .confirmationDialog(
            "Delete this withdrawal?",
            isPresented: $confirmsDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Withdrawal", role: .destructive) {
                Task { await deleteCurrent() }
            }
        } message: {
            Text("This removes the withdrawal and updates your account balance. It cannot be undone.")
        }
        .accessibilityIdentifier("withdrawals.detail.\(historyItemID)")
    }

    @ViewBuilder
    private func detailContent(item: PayoutHistoryItem, account: TradingAccount) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                headerBlock(item: item, account: account)
                if let cycle = cycle(for: item) {
                    cycleFacts(cycle)
                }
                if let notes = trimmedNotes(item.note) {
                    notesBlock(notes)
                }
                if let imageURL = trimmedNotes(item.imageURL), let url = URL(string: imageURL) {
                    pictureBlock(url)
                }
                achievementActionBlock(item: item, account: account)
                if item.isEditable {
                    Button("Delete Withdrawal", role: .destructive) {
                        confirmsDelete = true
                    }
                    .accessibilityIdentifier("withdrawals.detail.delete")
                }
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

    private func cycleFacts(_ cycle: AccountPayoutCycle) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            if let before = cycle.balanceBeforePayout {
                factRow("Balance before", DashboardViewModel.money(before))
            }
            if let after = cycle.balanceAfterPayout {
                factRow("Balance after", DashboardViewModel.money(after))
            }
            if let behavior = cycle.drawdownBehavior {
                factRow("Drawdown", behavior.title)
            }
            if let number = cycle.cycleNumber {
                factRow("Cycle", "\(number)")
            }
        }
    }

    private func factRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .experienceStyle(.subheadline, color: colors.secondaryText)
            Spacer(minLength: ExperienceSpacing.sm)
            Text(value)
                .experienceStyle(.subheadline, color: colors.primaryText)
        }
    }

    private func pictureBlock(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text("Picture")
                .experienceStyle(.headline, color: colors.primaryText)
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                case .failure:
                    Text("Picture unavailable")
                        .experienceStyle(.footnote, color: colors.tertiaryText)
                default:
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
        }
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

    private func cycle(for item: PayoutHistoryItem) -> AccountPayoutCycle? {
        guard item.source == .fundedCycle else { return nil }
        let cycleID = item.id.replacingOccurrences(of: "cycle:", with: "")
        return withdrawalsHistory.cyclesByAccount[item.accountID]?.first { $0.id == cycleID }
    }

    private func beginEdit() {
        guard let item = historyItem, item.ledgerEntryID != nil else { return }
        editorDraft = AccountPayoutEntryDraft(
            amountDigits: NumericInputFieldSupport.seedEditingText(
                from: item.amount,
                style: .unsignedCurrency
            ),
            payoutDate: item.date,
            note: item.note ?? "",
            imageURL: item.imageURL
        )
        showsEditor = true
    }

    private func deleteCurrent() async {
        guard let item = historyItem, let entryID = item.ledgerEntryID else { return }
        let imageURL = item.imageURL
        let deleted = await accountsViewModel.deletePayout(entryID: entryID, accountID: item.accountID)
        guard deleted else { return }
        await OwnedMediaStorageCleanup.removePublicObjects(
            urls: [imageURL],
            storage: data.objectStorage
        )
        dismiss()
    }

    private func hydrate() async {
        defer { didFinishHydrate = true }
        guard let userID = await data.session.currentUserID else { return }
        imageOwnerID = userID.rawValue
        let profileID = ProfileID(userID.rawValue)
        withdrawalsHistory.bindProfile(profileID)
        withdrawalsHistory.hydrateFromSessionCaches(profileID: profileID)
        accountsViewModel.seedWithdrawalsAccountsFromSessionCache()
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
