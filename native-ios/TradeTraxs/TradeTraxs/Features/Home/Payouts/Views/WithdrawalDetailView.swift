import SwiftUI

/// Row id for ``SettingsRoute/withdrawalDetail``. The settings path cannot carry the id.
@MainActor
enum WithdrawalDetailSelection {
    static var historyItemID: String?

    static func stage(_ historyItemID: String) {
        self.historyItemID = historyItemID
    }
}

/// Read-only withdrawal / payout history detail, optional post-as-achievement (no ledger mutation).
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
    @State private var showsFirmPicker = false

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
                    ExperienceLoadingSpinner(message: "Loading withdrawal…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ExperienceEmptyState(
                        icon: .payouts,
                        title: "Withdrawal unavailable",
                        message: "This withdrawal could not be loaded. Pull to refresh from Withdrawals."
                    )
                }
            } else if !didFinishHydrate {
                ExperienceLoadingSpinner(message: "Loading withdrawal…")
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
        .navigationBarBackButtonHidden(true)
        .experienceArrowBackToolbarButton(action: dismiss.callAsFunction)
        .navigationInteractivePopFromLeadingEdgeOnly()
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if showsDetailOverflowMenu {
                ToolbarItem(placement: .topBarTrailing) {
                    detailOverflowMenu
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
        .sheet(isPresented: $showsFirmPicker) {
            firmPickerSheet
        }
        .accessibilityIdentifier("withdrawals.detail.\(historyItemID)")
    }

    private var showsDetailOverflowMenu: Bool {
        guard let item = historyItem else { return false }
        if item.isEditable { return true }
        if item.source == .fundedCycle { return true }
        return showsPropFirmFeatures(item: item, account: account)
    }

    private var showsEditAchievementAction: Bool {
        guard let item = historyItem else { return false }
        return showsPropFirmFeatures(item: item, account: account)
    }

    @ViewBuilder
    private var detailOverflowMenu: some View {
        Menu {
            if showsEditAchievementAction {
                Button("Edit Achievement", systemImage: "building.2") {
                    prepareFirmPickerDraft()
                    showsFirmPicker = true
                }
                .accessibilityIdentifier("withdrawals.detail.editAchievement")
            }
            if historyItem?.isEditable == true {
                Button("Edit", systemImage: "square.and.pencil") {
                    beginEdit()
                }
                .accessibilityIdentifier("withdrawals.detail.edit")
                Button("Delete Withdrawal", systemImage: "trash", role: .destructive) {
                    confirmsDelete = true
                }
                .accessibilityIdentifier("withdrawals.detail.delete")
            } else if historyItem?.source == .fundedCycle {
                Button("Delete Payout", systemImage: "trash", role: .destructive) {
                    showsDrawdownDelete = true
                }
                .disabled(isDeletingPropPayout)
                .accessibilityIdentifier("withdrawals.detail.deletePayout")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(
                    width: ExperienceAccessibility.minTouchTarget,
                    height: ExperienceAccessibility.minTouchTarget
                )
                .contentShape(Rectangle())
                .experienceControlHitTarget()
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("withdrawals.detail.overflow")
    }

    @ViewBuilder
    private func detailContent(item: PayoutHistoryItem, account: TradingAccount?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                summaryCard(item: item, account: account)
                if let cycle = cycle(for: item) {
                    payoutDetailsCard(cycle)
                }
                if showsPropFirmFeatures(item: item, account: account), resolvedFirmName == nil {
                    assignPropFirmRow(item: item)
                }
                if account != nil, let notes = trimmedNotes(item.note) {
                    notesBlock(notes)
                }
                if let imageURL = trimmedNotes(item.imageURL), let url = URL(string: imageURL) {
                    pictureBlock(url)
                }
                if let account {
                    achievementActionBlock(item: item, account: account)
                }
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.vertical, ExperienceSpacing.md)
        }
    }

    private func summaryCard(item: PayoutHistoryItem, account: TradingAccount?) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text(formatPayoutMoney(item.amount))
                .font(.system(.title2, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(colors.primaryText)

            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                if showsPropFirmFeatures(item: item, account: account), let firm = resolvedFirmName {
                    propFirmSummaryRow(firmName: firm)
                }
                Text(accountTypeLine(account: account, item: item))
                    .experienceStyle(.subheadline, color: colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(TradeDisplay.dateText(item.date))
                    .experienceStyle(.caption, color: colors.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ExperienceSpacing.md)
        .experienceDashboardCard(prominence: .standard)
    }

    private func propFirmSummaryRow(firmName: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.xs) {
            Text("Prop firm")
                .experienceStyle(.caption, color: colors.tertiaryText)
            Text(firmName)
                .experienceStyle(.subheadline, color: colors.primaryText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func payoutDetailsCard(_ cycle: AccountPayoutCycle) -> some View {
        let rows = payoutDetailRows(for: cycle)
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                detailFactRow(row.label, row.value)
                if index < rows.count - 1 {
                    payoutDetailDivider()
                }
            }
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.vertical, ExperienceSpacing.xs)
        .experienceDashboardCard(prominence: .standard)
    }

    private func payoutDetailRows(for cycle: AccountPayoutCycle) -> [(label: String, value: String)] {
        var rows: [(String, String)] = []
        if let before = cycle.balanceBeforePayout {
            rows.append(("Balance Before", formatPayoutMoney(before)))
        }
        if let after = cycle.balanceAfterPayout {
            rows.append(("Balance After", formatPayoutMoney(after)))
        }
        if let behavior = cycle.drawdownBehavior {
            rows.append(("Drawdown", behavior.title))
        }
        if let number = cycle.cycleNumber {
            rows.append(("Cycle", "\(number)"))
        }
        return rows
    }

    private func payoutDetailDivider() -> some View {
        ExperienceDivider()
    }

    private func detailFactRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.sm) {
            Text(title)
                .experienceStyle(.subheadline, color: colors.secondaryText)
            Spacer(minLength: ExperienceSpacing.sm)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.medium).monospacedDigit())
                .foregroundStyle(colors.primaryText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, ExperienceSpacing.xs + 2)
    }

    private func assignPropFirmRow(item: PayoutHistoryItem) -> some View {
        Button {
            prepareFirmPickerDraft()
            showsFirmPicker = true
        } label: {
            HStack(spacing: ExperienceSpacing.sm) {
                Text("Assign Prop Firm")
                    .experienceStyle(.subheadline, color: colors.accent)
                    .fontWeight(.semibold)
                Spacer(minLength: ExperienceSpacing.xs)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(colors.tertiaryText)
            }
            .padding(ExperienceSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
        }
        .buttonStyle(.experiencePlain)
        .experienceDashboardCard(prominence: .standard)
        .accessibilityIdentifier("withdrawals.detail.assignFirm")
    }

    private var firmPickerSheet: some View {
        NavigationStack {
            List {
                if !firmSuggestions.isEmpty {
                    Section("Existing firms") {
                        ForEach(firmSuggestions, id: \.self) { name in
                            Button {
                                firmDraft = name
                            } label: {
                                HStack {
                                    Text(name)
                                        .foregroundStyle(colors.primaryText)
                                    Spacer(minLength: 0)
                                    if firmDraft == name {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(colors.accent)
                                    }
                                }
                            }
                        }
                    }
                }
                Section("Firm name") {
                    TextField("Apex, Topstep", text: $firmDraft)
                        .textInputAutocapitalization(.words)
                        .accessibilityLabel("Prop firm name")
                }
                if let firmStatus, !firmStatus.isEmpty {
                    Section {
                        Text(firmStatus)
                            .experienceStyle(.caption, color: colors.secondaryText)
                    }
                }
                if assignedFirmName != nil, let item = historyItem {
                    Section {
                        Button("Remove assignment", role: .destructive) {
                            Task {
                                await clearFirm(for: item)
                                showsFirmPicker = false
                            }
                        }
                        .disabled(isSavingFirm)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .experienceScreenBackground()
            .experienceNavigationTitle("Edit Achievement")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showsFirmPicker = false }
                        .disabled(isSavingFirm)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSavingFirm ? "Saving…" : "Save") {
                        guard let item = historyItem else { return }
                        Task {
                            if await saveFirm(for: item) {
                                showsFirmPicker = false
                            }
                        }
                    }
                    .disabled(
                        isSavingFirm
                        || firmDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
        .experienceSheetChrome(detents: [.medium, .large])
    }

    private func prepareFirmPickerDraft() {
        if firmDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let assigned = assignedFirmName {
                firmDraft = assigned
            } else if let linked = linkedFirmName {
                firmDraft = linked
            }
        }
    }

    private func showsPropFirmFeatures(item: PayoutHistoryItem, account: TradingAccount?) -> Bool {
        PayoutHistorySupport.isPropPayout(item, account: account)
            || item.source == .achievementLive
            || item.source == .achievementProp
    }

    private var resolvedFirmName: String? {
        assignedFirmName ?? linkedFirmName
    }

    private func formatPayoutMoney(_ value: Decimal) -> String {
        NumberDisplay.currency(value, minimumFractionDigits: 2, maximumFractionDigits: 2)
    }

    @discardableResult
    private func saveFirm(for item: PayoutHistoryItem) async -> Bool {
        guard let userID = await data.session.currentUserID else { return false }
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
            await refreshAfterFirmAssignmentChanged(for: item)
            return true
        } catch {
            firmStatus = UserFacingError.message(for: error)
            return false
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
            await refreshAfterFirmAssignmentChanged(for: item)
        } catch {
            firmStatus = UserFacingError.message(for: error)
        }
    }

    private func refreshAfterFirmAssignmentChanged(for item: PayoutHistoryItem) async {
        await loadFirmAssignment(for: item)
        NotificationCenter.default.post(name: .propFirmPayoutAssignmentsDidChange, object: nil)
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
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Picture")
                .experienceStyle(.subheadline, color: colors.secondaryText)
                .fontWeight(.semibold)
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
                    ExperienceIndeterminateProgress()
                }
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous))
        }
        .padding(ExperienceSpacing.md)
        .experienceDashboardCard(prominence: .standard)
    }

    private func notesBlock(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Notes")
                .experienceStyle(.subheadline, color: colors.secondaryText)
                .fontWeight(.semibold)
            Text(notes)
                .experienceStyle(.body, color: colors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(ExperienceSpacing.md)
        .experienceDashboardCard(prominence: .standard)
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
                .experienceDashboardNestedCard(cornerRadius: ExperienceRadius.md)
            }
            .buttonStyle(.experiencePlain)
            .accessibilityIdentifier("withdrawals.detail.postedAchievement")
        } else if PropFirmPayoutCycleSupport.achievementPrefill(for: item, account: account) != nil {
            ExperienceButton(title: "Post as Achievement", kind: .primary) {
                postAsAchievement(item: item, account: account)
            }
            .frame(maxWidth: .infinity)
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

    private func accountTypeLine(account: TradingAccount?, item: PayoutHistoryItem) -> String {
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
        .experienceSheetChrome(detents: [.medium])
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
