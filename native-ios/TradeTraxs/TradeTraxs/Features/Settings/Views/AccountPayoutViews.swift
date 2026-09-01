import SwiftUI

/// Owner-only manual payout rows — shared by Manage Accounts and Dashboard Payouts.
struct AccountPayoutListContent: View {
    @Bindable var viewModel: ManageAccountsViewModel
    let accountID: TradingAccountID
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
                Label("Add Payout", systemImage: "plus.circle")
            }
        }
    }
}

struct AccountPayoutEditorSheet: View {
    @Bindable var viewModel: ManageAccountsViewModel
    let accountID: TradingAccountID
    let editingEntryID: AccountPayoutEntryID?
    @Binding var draft: AccountPayoutEntryDraft
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            Form {
                SettingsLabeledField(title: "Amount", helper: "USD") {
                    TextField("0", text: $draft.amountDigits)
                        .keyboardType(.decimalPad)
                }
                DatePicker("Payout Date", selection: $draft.payoutDate, displayedComponents: .date)
                SettingsLabeledField(title: "Note", helper: "Optional") {
                    TextField("Optional", text: $draft.note, axis: .vertical)
                        .lineLimit(2...3)
                }
            }
            .experienceNavigationTitle(editingEntryID == nil ? "Add Payout" : "Edit Payout")
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
