import SwiftUI

/// Completed payout cycles from `account_payout_cycles` — funded prop-firm history.
struct FundedPayoutCycleHistoryContent: View {
    let cycles: [AccountPayoutCycle]

    @Environment(\.themeColors) private var colors

    var body: some View {
        if cycles.isEmpty {
            Text("No recorded payouts yet")
                .experienceStyle(.footnote, color: colors.secondaryText)
                .padding(.top, ExperienceSpacing.xxs)
        } else {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                ForEach(cycles) { cycle in
                    VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                        HStack {
                            if let amount = cycle.payoutAmount {
                                Text(TradeDisplay.pnlText(Money(amount: amount)))
                                    .experienceStyle(.body, color: colors.primaryText)
                            }
                            Spacer(minLength: 0)
                            if let endedAt = cycle.endedAt {
                                Text(TradeDisplay.dateText(endedAt))
                                    .experienceStyle(.caption, color: colors.secondaryText)
                            }
                        }
                        if let after = cycle.balanceAfterPayout {
                            Text("Balance after: \(DashboardViewModel.money(after))")
                                .experienceStyle(.caption, color: colors.tertiaryText)
                        }
                    }
                }
            }
            .padding(.top, ExperienceSpacing.xxs)
        }
    }
}

/// Owner-only manual payout rows — shared by Manage Accounts and Dashboard Payouts.
struct AccountPayoutListContent: View {
    @Bindable var viewModel: ManageAccountsViewModel
    let accountID: TradingAccountID
    var addButtonTitle: String = "Add Payout"
    var onAdd: () -> Void
    var onEdit: (AccountPayoutEntry) -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        if viewModel.isLoadingPayouts, viewModel.payoutEntries(for: accountID).isEmpty {
            HStack {
                ProgressView()
                Text("Loading payouts…")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }
        } else if let payoutError = viewModel.payoutError,
                  viewModel.payoutEntries(for: accountID).isEmpty {
            SettingsInlineError(message: payoutError) {
                Task { await viewModel.loadPayoutEntries(for: accountID) }
            }
        } else {
            let rows = viewModel.payoutEntries(for: accountID)
            if rows.isEmpty {
                Text("No payout entries yet")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            } else {
                ForEach(rows) { entry in
                    VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                        HStack {
                            Text(TradeDisplay.pnlText(entry.amount))
                                .experienceStyle(.body, color: colors.primaryText)
                            Spacer(minLength: 0)
                            Text(TradeDisplay.dateText(entry.payoutDate))
                                .experienceStyle(.caption, color: colors.secondaryText)
                        }
                        if let note = entry.note, !note.isEmpty {
                            Text(note)
                                .experienceStyle(.caption, color: colors.tertiaryText)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { _ = await viewModel.deletePayout(entryID: entry.id, accountID: accountID) }
                        } label: {
                            Text("Delete")
                        }
                        Button {
                            onEdit(entry)
                        } label: {
                            Text("Edit")
                        }
                    }
                }
            }

            Button(action: onAdd) {
                Label(addButtonTitle, systemImage: "plus.circle")
            }
        }
    }
}

enum AccountPayoutEditorCopy: Sendable {
    case manageAccount
    case payoutHistory

    var addTitle: String {
        switch self {
        case .manageAccount: return "Add Payout"
        case .payoutHistory: return "Edit Payout"
        }
    }

    var editTitle: String { "Edit Payout" }

    var amountLabel: String { "Amount" }
    var dateLabel: String { "Payout Date" }
}

struct AccountPayoutEditorSheet: View {
    @Bindable var viewModel: ManageAccountsViewModel
    let accountID: TradingAccountID
    let editingEntryID: AccountPayoutEntryID?
    @Binding var draft: AccountPayoutEntryDraft
    @Binding var isPresented: Bool
    var copy: AccountPayoutEditorCopy = .manageAccount

    var body: some View {
        NavigationStack {
            Form {
                SettingsLabeledField(title: copy.amountLabel, helper: "USD") {
                    TextField("0", text: $draft.amountDigits.numericInput(.unsignedCurrency))
                        .keyboardType(.decimalPad)
                }
                DatePicker(copy.dateLabel, selection: $draft.payoutDate, displayedComponents: .date)
                SettingsLabeledField(title: "Note", helper: "Optional") {
                    TextField("Optional", text: $draft.note, axis: .vertical)
                        .lineLimit(2...3)
                }
            }
            .experienceDashboardGroupedRows()
            .experienceNavigationTitle(
                editingEntryID == nil ? copy.addTitle : copy.editTitle
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(viewModel.isSaving)
                }
            }
        }
        .presentationDetents([.medium])
        .experienceProtectedFormDismiss()
    }

    private func save() async {
        let ok: Bool
        if let editingEntryID {
            ok = await viewModel.updatePayout(
                entryID: editingEntryID,
                accountID: accountID,
                draft: draft
            )
        } else {
            ok = await viewModel.createPayout(accountID: accountID, draft: draft)
        }
        if ok { isPresented = false }
    }
}
