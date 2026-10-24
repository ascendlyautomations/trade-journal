import SwiftUI

/// Row id for ``SettingsRoute/withdrawalDetail``. The settings path cannot carry the id.
@MainActor
enum WithdrawalDetailSelection {
    static var historyItemID: String?

    static func stage(_ historyItemID: String) {
        self.historyItemID = historyItemID
    }
}

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
    @State private var editingEntryID: AccountPayoutEntryID?
    @State private var editingAccountID: TradingAccountID?
    @State private var editorDraft = AccountPayoutEntryDraft(amountDigits: "", payoutDate: .now, note: "")
    @State private var confirmsDelete = false
    @State private var showsDrawdownDelete = false
    @State private var isDeletingPropPayout = false
    @State private var imageOwnerID: String?
    @State private var firmDraft = ""
    @State private var firmSuggestions: [String] = []
    @State private var assignedFirmName: String?
    @State private var linkedFirmName: String?
    @State private var firmNameFromAccount = false
    @State private var firmStatus: String?
    @State private var isSavingFirm = false

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
        let recorded = PayoutHistorySupport.buildHistory(
            accounts: accountsViewModel.accounts,
            entriesByAccount: withdrawalsHistory.ledgerByAccount,
            cyclesByAccount: withdrawalsHistory.cyclesByAccount
        )
        let items = (recorded + withdrawalsHistory.achievementPayouts).sorted { $0.date > $1.date }
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
        guard let item = historyItem else { return "Withdrawal" }
        return PayoutHistorySupport.isPropPayout(item, account: account) ? "Payout" : "Withdrawal"
    }

    var body: some View {
        Group {
            if let item = historyItem {
                let fromAchievement = item.source == .achievementProp || item.source == .achievementLive
                if account != nil || fromAchievement {
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
            if imageOwnerID == nil {
                imageOwnerID = withdrawalsHistory.profileID?.rawValue
            }
        }
        .task {
            await hydrate()
        }
        .sheet(isPresented: $showsEditor) {
            if let editingEntryID, let editingAccountID {
                AccountPayoutEditorSheet(
                    viewModel: accountsViewModel,
                    accountID: editingAccountID,
                    editingEntryID: editingEntryID,
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
            Text("The withdrawal amount goes back on the account balance. This cannot be undone.")
        }
        .sheet(isPresented: $showsDrawdownDelete) {
            propPayoutDeleteSheet
        }
        .accessibilityIdentifier("withdrawals.detail.\(historyItemID)")
    }

    @ViewBuilder
    private func detailContent(item: PayoutHistoryItem, account: TradingAccount?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                headerBlock(item: item, account: account)
                if let cycle = cycle(for: item) {
                    cycleFacts(cycle)
                }
                if account != nil, let notes = trimmedNotes(item.note) {
                    notesBlock(notes)
                }
                if let imageURL = trimmedNotes(item.imageURL), let url = URL(string: imageURL) {
                    pictureBlock(url)
                }
                if PayoutHistorySupport.isPropPayout(item, account: account)
                    || item.source == .achievementLive
                    || item.source == .achievementProp {
                    firmAssignmentBlock(item: item)
                }
                if let account {
                    achievementActionBlock(item: item, account: account)
                }
                if item.isEditable {
                    Button("Delete Withdrawal", role: .destructive) {
                        confirmsDelete = true
                    }
                    .accessibilityIdentifier("withdrawals.detail.delete")
                } else if item.source == .fundedCycle {
                    Button("Delete Payout", role: .destructive) {
                        showsDrawdownDelete = true
                    }
                    .disabled(isDeletingPropPayout)
                    .accessibilityIdentifier("withdrawals.detail.deletePayout")
                }
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.vertical, ExperienceSpacing.lg)
        }
    }

    private func headerBlock(item: PayoutHistoryItem, account: TradingAccount?) -> some View {
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

    private func firmAssignmentBlock(item: PayoutHistoryItem) -> some View {
        let current = assignedFirmName ?? linkedFirmName
        return VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Prop firm")
                .experienceStyle(.headline, color: colors.primaryText)
            Text(current ?? "Unassigned")
                .experienceStyle(.body, color: colors.primaryText)
            if assignedFirmName == nil, linkedFirmName != nil {
                Text(firmNameFromAccount ? "From the account name" : "From the linked expense")
                    .experienceStyle(.caption, color: colors.secondaryText)
            }
            Text("Assigning a firm updates the expense tracker for this payout. The payout amount and account balance stay the same.")
                .experienceStyle(.caption, color: colors.secondaryText)
            if !firmSuggestions.isEmpty {
                Menu {
                    ForEach(firmSuggestions, id: \.self) { name in
                        Button(name) { firmDraft = name }
                    }
                } label: {
                    Text("Use an existing firm")
                        .experienceStyle(.subheadline, color: colors.accent)
                }
            }
            TextField("Apex, Topstep", text: $firmDraft)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Prop firm name")
            if let firmStatus {
                Text(firmStatus)
                    .experienceStyle(.caption, color: colors.secondaryText)
            }
            ExperienceButton(
                title: isSavingFirm ? "Saving…" : "Assign to prop firm",
                kind: .primary
            ) {
                Task { await saveFirm(for: item) }
            }
            .disabled(isSavingFirm)
            .accessibilityIdentifier("withdrawals.detail.assignFirm")
            if assignedFirmName != nil {
                Button {
                    Task { await clearFirm(for: item) }
                } label: {
                    Text("Remove assignment")
                        .experienceStyle(.subheadline, color: colors.secondaryText)
                }
                .disabled(isSavingFirm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ExperienceSpacing.sm)
        .background(colors.fillSecondary.opacity(0.35), in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
    }

    private func saveFirm(for item: PayoutHistoryItem) async {
        guard let userID = await data.session.currentUserID else { return }
        isSavingFirm = true
        firmStatus = nil
        defer { isSavingFirm = false }
        do {
            let repository = PropFirmExpenseRepository(supabase: data.supabase)
            try await repository.savePayoutAssignment(
                userID: ProfileID(userID.rawValue),
                payoutKey: item.id,
                firmName: firmDraft
            )
            let saved = PropFirmExpenseRepository.normalizedFirmName(firmDraft) ?? firmDraft
            assignedFirmName = saved
            firmDraft = saved
            PropFirmPayoutAssignmentStore.shared.set(name: saved, for: item.id)
            firmStatus = "Firm saved for this payout."
        } catch {
            firmStatus = UserFacingError.message(for: error)
        }
    }

    private func clearFirm(for item: PayoutHistoryItem) async {
        guard let userID = await data.session.currentUserID else { return }
        isSavingFirm = true
        firmStatus = nil
        defer { isSavingFirm = false }
        do {
            try await PropFirmExpenseRepository(supabase: data.supabase).clearPayoutAssignment(
                userID: ProfileID(userID.rawValue),
                payoutKey: item.id
            )
            assignedFirmName = nil
            firmDraft = ""
            PropFirmPayoutAssignmentStore.shared.set(name: nil, for: item.id)
            firmStatus = nil
        } catch {
            firmStatus = UserFacingError.message(for: error)
        }
    }

    private func loadFirmAssignment(for item: PayoutHistoryItem) async {
        guard let userID = await data.session.currentUserID else { return }
        let profileID = ProfileID(userID.rawValue)
        let repository = PropFirmExpenseRepository(supabase: data.supabase)
        async let assignmentTask = repository.payoutAssignments(userID: profileID)
        async let expenseTask = repository.list(userID: profileID)
        if let names = try? await assignmentTask {
            PropFirmPayoutAssignmentStore.shared.replace(names)
            assignedFirmName = names[item.id]
            if firmDraft.isEmpty, let assigned = names[item.id] {
                firmDraft = assigned
            }
        }
        guard let expenses = try? await expenseTask else { return }
        var seen: [String: String] = [:]
        for expense in expenses {
            guard let name = PropFirmExpenseRepository.normalizedFirmName(expense.propFirmName) else { continue }
            if seen[name.lowercased()] == nil { seen[name.lowercased()] = name }
        }
        firmSuggestions = seen.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let linked = PropFirmYearOverviewBuilder.attributedFirmName(accountID: item.accountID, expenses: expenses)
        if let linked {
            linkedFirmName = linked
            firmNameFromAccount = false
        } else {
            let inferred = TradingAccountDisplay.inferPropFirmName(
                accountsViewModel.accounts.first { $0.id == item.accountID }?.name
            )
            linkedFirmName = inferred.isEmpty ? nil : inferred
            firmNameFromAccount = linkedFirmName != nil
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
            .buttonStyle(.experiencePlain)
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

    private func accountLine(account: TradingAccount?, item: PayoutHistoryItem) -> String {
        let kind = PayoutHistorySupport.isPropPayout(item, account: account) ? "Prop payout" : "Live withdrawal"
        guard let account else {
            let title = item.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return title.isEmpty ? kind : "\(title) · \(kind)"
        }
        let trimmedName = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let mode = TradingAccountDisplay.ownerDropdownModeLabel(account.mode)
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
        guard let item = historyItem, let entryID = item.ledgerEntryID else { return }
        editingEntryID = entryID
        editingAccountID = item.accountID
        PayoutEditDiagnostics.open(
            historyItemID: item.id,
            editable: true,
            surface: "editor"
        )
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

    private var propPayoutDeleteSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                Text("This payout goes back on the account balance. Where should the drawdown move?")
                    .experienceStyle(.body, color: colors.secondaryText)
                ExperienceButton(
                    title: "Reset drawdown to account value",
                    kind: .secondary,
                    isEnabled: !isDeletingPropPayout,
                    isLoading: isDeletingPropPayout,
                    accessibilityIdentifier: "withdrawals.detail.deletePayout.reset"
                ) {
                    Task { await deletePropPayout(behavior: .resetToAccount) }
                }
                ExperienceButton(
                    title: "Keep trailing drawdown",
                    kind: .secondary,
                    isEnabled: !isDeletingPropPayout,
                    accessibilityIdentifier: "withdrawals.detail.deletePayout.trailing"
                ) {
                    Task { await deletePropPayout(behavior: .keepTrailing) }
                }
                if let formError = accountsViewModel.formError, !formError.isEmpty {
                    Text(formError)
                        .experienceStyle(.footnote, color: colors.negativePnL)
                }
            }
            .padding(ExperienceSpacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .experienceScreenBackground()
            .experienceNavigationTitle("Delete payout")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showsDrawdownDelete = false }
                        .disabled(isDeletingPropPayout)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func deletePropPayout(behavior: PayoutDrawdownBehavior) async {
        guard let item = historyItem, item.source == .fundedCycle else { return }
        let cycleID = item.id.replacingOccurrences(of: "cycle:", with: "")
        isDeletingPropPayout = true
        let deleted = await accountsViewModel.deletePropPayout(
            cycleID: cycleID,
            accountID: item.accountID,
            drawdownBehavior: behavior
        )
        isDeletingPropPayout = false
        guard deleted else { return }
        showsDrawdownDelete = false
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
        let recorded = PayoutHistorySupport.buildHistory(
            accounts: accountsViewModel.accounts,
            entriesByAccount: withdrawalsHistory.ledgerByAccount,
            cyclesByAccount: withdrawalsHistory.cyclesByAccount
        )
        let extras = await PayoutHistorySupport.loadMissingAchievementPayouts(
            achievements: data.achievements,
            profileID: profileID,
            recorded: recorded
        )
        withdrawalsHistory.setAchievementPayouts(extras)
        if let item = historyItem,
           PayoutHistorySupport.isPropPayout(item, account: account)
            || item.source == .achievementLive
            || item.source == .achievementProp {
            await loadFirmAssignment(for: item)
        }
        do {
            let rows = try await data.achievements.withdrawalAchievementLinks(for: profileID)
            linkStore.applyFetched(rows)
        } catch {
            WithdrawalsTrace.log("achievementLinksFetchFailed", detail: error.localizedDescription)
        }
    }
}
