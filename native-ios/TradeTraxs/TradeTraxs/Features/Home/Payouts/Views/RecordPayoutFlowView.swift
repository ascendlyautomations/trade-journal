import SwiftUI

/// Funded prop-firm Record Payout — mirrors web PayoutSetupModal + confirm + optional achievement share.
struct RecordPayoutFlowView: View {
    @State private var viewModel: RecordPayoutFlowViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors

    init(
        accountID: TradingAccountID,
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator
    ) {
        _viewModel = State(
            initialValue: RecordPayoutFlowViewModel(
                accountID: accountID,
                trades: data.trades,
                session: data.session,
                detailCache: data.detailCache,
                navigationCoordinator: navigationCoordinator
            )
        )
    }

    init(viewModel: RecordPayoutFlowViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .loading:
                    ProgressView("Loading payout setup…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    ExperienceErrorState(
                        title: "Couldn't open Record Payout",
                        message: message,
                        onRetry: { Task { await viewModel.loadIfNeeded() } }
                    )
                case .ready, .recording:
                    stepContent
                }
            }
            .experienceScreenBackground()
            .experienceNavigationTitle("Record Payout")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await viewModel.loadIfNeeded() }
        }
        .experienceProtectedFormDismiss()
        .accessibilityIdentifier("recordPayout.flow")
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.step {
        case .setup:
            setupForm
        case .confirm:
            confirmStep
        case .sharePrompt:
            sharePrompt
        }
    }

    private var setupForm: some View {
        Form {
            Section {
                LabeledContent("Account", value: viewModel.accountName)
                    .experienceDashboardListRow()
                LabeledContent("Balance before payout", value: viewModel.balanceBeforeDisplay)
                    .experienceDashboardListRow()
            } header: {
                Text("Account")
            }

            Section {
                SettingsLabeledField(title: "Payout amount", helper: "USD") {
                    RecordPayoutCurrencyField(
                        amountText: $viewModel.payoutAmountDigits,
                        onEditingChange: { viewModel.syncBalanceAfterFromPayoutAmount() }
                    )
                }
                .experienceDashboardListRow()
                SettingsLabeledField(title: "Balance after payout", helper: "USD") {
                    RecordPayoutCurrencyField(amountText: $viewModel.balanceAfterDigits)
                }
                .experienceDashboardListRow()
                DatePicker("Payout date", selection: $viewModel.payoutDate, in: ...Date(), displayedComponents: .date)
                    .experienceDashboardListRow()
            } header: {
                Text("Payout")
            }

            Section {
                Picker("Drawdown after payout", selection: $viewModel.drawdownBehavior) {
                    ForEach(PayoutDrawdownBehavior.allCases, id: \.self) { behavior in
                        Text(behavior.title).tag(behavior)
                    }
                }
                .experienceDashboardListRow()
                Text(viewModel.drawdownBehavior.subtitle)
                    .font(.footnote)
                    .foregroundStyle(colors.secondaryText)
                    .experienceDashboardListRow()
                Toggle("Remember this drawdown choice", isOn: $viewModel.rememberDrawdownBehavior)
                    .experienceDashboardListRow()
            } header: {
                Text("Drawdown")
            }

            if let formError = viewModel.formError {
                Section {
                    Text(formError)
                        .foregroundStyle(colors.loss)
                        .font(.footnote)
                        .experienceDashboardListRow()
                }
            }

            Section {
                Button("Continue") {
                    viewModel.advanceToConfirm()
                }
                .tint(colors.accent)
                .disabled(!viewModel.canAdvanceFromSetup || viewModel.phase == .recording)
                .experienceDashboardListRow()
            }
        }
        .listRowSeparatorTint(colors.separator)
        .scrollDismissesKeyboard(.interactively)
        .experienceDashboardGroupedRows()
    }

    private var confirmStep: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
            Text("Confirm payout")
                .experienceStyle(.title3, color: colors.primaryText)
            Text(
                "Recording this payout will close the current payout cycle and start a new cycle from your post-payout balance. Historical trades and lifetime statistics stay unchanged; current cycle progress resets."
            )
            .experienceStyle(.subheadline, color: colors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)

            if let formError = viewModel.formError {
                Text(formError)
                    .experienceStyle(.footnote, color: colors.loss)
            }

            Spacer(minLength: 0)

            HStack(spacing: ExperienceSpacing.md) {
                ExperienceButton(title: "Back", kind: .secondary) {
                    viewModel.backToSetup()
                }
                ExperienceButton(
                    title: "Record Payout",
                    kind: .primary,
                    isLoading: viewModel.phase == .recording
                ) {
                    Task { _ = await viewModel.recordPayout() }
                }
            }
        }
        .padding(ExperienceSpacing.lg)
    }

    private var sharePrompt: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
            Text("Payout recorded")
                .experienceStyle(.title3, color: colors.primaryText)
            Text("Your payout cycle was updated. Share this payout as a public Achievement?")
                .experienceStyle(.subheadline, color: colors.secondaryText)

            Spacer(minLength: 0)

            ExperienceButton(title: "Share as Achievement", kind: .primary) {
                viewModel.openShareAchievementFlow { dismiss() }
            }
            ExperienceButton(title: "Not now", kind: .secondary) {
                dismiss()
            }
        }
        .padding(ExperienceSpacing.lg)
    }
}

/// Focus-aware USD field — raw decimal input while editing, `$1,234.56` when idle.
private struct RecordPayoutCurrencyField: View {
    @Binding var amountText: String
    var onEditingChange: (() -> Void)? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(isFocused ? "0" : "$0.00", text: fieldBinding)
            .keyboardType(.decimalPad)
            .focused($isFocused)
            .experienceFormFocusSync($isFocused)
    }

    private var fieldBinding: Binding<String> {
        Binding(
            get: {
                guard isFocused else {
                    guard let amount = CurrencyAmountFieldSupport.parse(amountText) else {
                        return amountText
                    }
                    return CurrencyAmountFieldSupport.formatDisplay(amount)
                }
                return amountText
            },
            set: { newValue in
                let sanitized = CurrencyAmountFieldSupport.sanitizeInput(newValue)
                if sanitized != amountText {
                    amountText = sanitized
                    onEditingChange?()
                }
            }
        )
    }
}
