import SwiftUI

/// Owner-only payout ledger — manual entries across all trading accounts.
struct PayoutsScreenView: View {
    @State private var viewModel: ManageAccountsViewModel
    @State private var payoutSheetContext: PayoutSheetContext?

    @Environment(\.themeColors) private var colors

    private struct PayoutSheetContext: Identifiable {
        let accountID: TradingAccountID
        let editingEntryID: AccountPayoutEntryID?
        var draft: AccountPayoutEntryDraft

        var id: String {
            accountID.rawValue + (editingEntryID?.rawValue ?? "new")
        }
    }

    init(data: DataEnvironment) {
        _viewModel = State(
            initialValue: ManageAccountsViewModel(
                trades: data.trades,
                session: data.session,
                detailCache: data.detailCache
            )
        )
    }

    init(viewModel: ManageAccountsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            if let error = viewModel.errorMessage, viewModel.accounts.isEmpty, !viewModel.isLoading {
                ExperienceErrorState(
                    title: "Couldn't load payouts",
                    message: error,
                    onRetry: { Task { await viewModel.refresh() } }
                )
            } else {
                payoutList
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Payouts")
        .toolbar(.hidden, for: .tabBar)
        .refreshable {
            await viewModel.refresh()
            await viewModel.loadAllPayoutEntries()
        }
        .task {
            viewModel.loadIfNeeded()
            await loadPayoutsWhenReady()
        }
        .sheet(item: $payoutSheetContext) { context in
            AccountPayoutEditorSheet(
                viewModel: viewModel,
                accountID: context.accountID,
                editingEntryID: context.editingEntryID,
                draft: bindingDraft(for: context),
                isPresented: Binding(
                    get: { payoutSheetContext != nil },
                    set: { if !$0 { payoutSheetContext = nil } }
                )
            )
        }
        .accessibilityIdentifier("payouts.home")
    }

    private var payoutList: some View {
        List {
            Section {
                introBlock
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if viewModel.isLoading, viewModel.accounts.isEmpty {
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading accounts…")
                            .experienceStyle(.footnote, color: colors.secondaryText)
                    }
                }
            } else if viewModel.accounts.isEmpty {
                Section {
                    SettingsIntroBlock(
                        title: "No trading accounts yet",
                        message: "Add an account from Manage Accounts to track manual payouts here."
                    )
                }
            } else {
                ForEach(viewModel.accounts) { account in
                    Section {
                        AccountPayoutListContent(
                            viewModel: viewModel,
                            accountID: account.id,
                            onAdd: { presentAddPayout(for: account.id) },
                            onEdit: { entry in presentEditPayout(entry, accountID: account.id) }
                        )
                    } header: {
                        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                            Text(TradingAccountDisplay.title(for: account, audience: .owner))
                            Text(viewModel.subtitle(for: account))
                                .font(.caption)
                                .foregroundStyle(colors.secondaryText)
                        }
                    }
                    .task(id: account.id.rawValue) {
                        await viewModel.loadPayoutEntries(for: account.id)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var introBlock: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text("Manual Payouts")
                .experienceStyle(.title2, color: colors.primaryText)
            Text("Private ledger entries for your accounts. Share payouts publicly by posting payout achievements.")
                .experienceStyle(.subheadline, color: colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ExperienceSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            colors.accent.opacity(0.16),
                            colors.fillSecondary.opacity(0.65),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.vertical, ExperienceSpacing.sm)
        .accessibilityIdentifier("payouts.intro")
    }

    private func presentAddPayout(for accountID: TradingAccountID) {
        payoutSheetContext = PayoutSheetContext(
            accountID: accountID,
            editingEntryID: nil,
            draft: AccountPayoutEntryDraft(amountDigits: "", payoutDate: .now, note: "")
        )
    }

    private func presentEditPayout(_ entry: AccountPayoutEntry, accountID: TradingAccountID) {
        payoutSheetContext = PayoutSheetContext(
            accountID: accountID,
            editingEntryID: entry.id,
            draft: AccountPayoutEntryDraft(
                amountDigits: NSDecimalNumber(decimal: entry.amount.amount).stringValue,
                payoutDate: entry.payoutDate,
                note: entry.note ?? ""
            )
        )
    }

    private func bindingDraft(for context: PayoutSheetContext) -> Binding<AccountPayoutEntryDraft> {
        Binding(
            get: { payoutSheetContext?.draft ?? context.draft },
            set: { newValue in
                payoutSheetContext?.draft = newValue
            }
        )
    }

    private func loadPayoutsWhenReady() async {
        let deadline = Date().addingTimeInterval(5)
        while viewModel.accounts.isEmpty, Date() < deadline {
            if !viewModel.isLoading { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        guard !viewModel.accounts.isEmpty else { return }
        await viewModel.loadAllPayoutEntries()
    }
}
