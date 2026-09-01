import SwiftUI

/// Dedicated Prop Firm account detail — rules, risk, targets, payouts.
struct PropFirmDetailView: View {
    let accountID: TradingAccountID
    @State private var viewModel: PropFirmDetailViewModel

    @Environment(\.themeColors) private var colors

    init(accountID: TradingAccountID, data: DataEnvironment) {
        self.accountID = accountID
        _viewModel = State(
            initialValue: PropFirmDetailViewModel(
                accountID: accountID,
                trades: data.trades,
                session: data.session,
                detailCache: data.detailCache,
                rpc: data.rpc,
                realtimeHub: data.realtimeHub
            )
        )
    }

    /// Tests.
    init(viewModel: PropFirmDetailViewModel) {
        self.accountID = viewModel.accountID
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            if let snapshot = viewModel.snapshot {
                ScrollView {
                    VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                        accountStatus(snapshot)
                        risk(snapshot)
                        targets(snapshot)
                        consistency(snapshot)
                        payouts(snapshot)
                    }
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.vertical, ExperienceSpacing.md)
                    .padding(.bottom, ExperienceSpacing.xl)
                }
            } else if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ExperienceEmptyState(
                    icon: .chart,
                    title: "Prop account unavailable",
                    message: viewModel.errorMessage ?? "Select a prop-firm account from the Dashboard."
                )
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle(viewModel.snapshot?.accountName ?? "Prop Firm")
        .task { await viewModel.loadIfNeeded() }
        .refreshable { await viewModel.refresh() }
        .onChange(of: TradeJournalMutationStore.shared.revision) { _, _ in
            Task { await viewModel.refresh() }
        }
        .onChange(of: AccountMutationStore.shared.revision) { _, _ in
            Task { await viewModel.refresh() }
        }
        .onDisappear { viewModel.onDisappear() }
        .accessibilityIdentifier("propFirm.detail")
    }

    // MARK: - Sections

    private func accountStatus(_ s: PropFirmStatusSnapshot) -> some View {
        section("Account Status") {
            row("Firm / Account", s.accountName)
            row("Phase", s.phaseLabel)
            row("Status", s.statusLabel)
            row("Starting balance", DashboardViewModel.money(s.startingBalance))
            row("Current balance", DashboardViewModel.money(s.currentBalance))
            row("Cycle P&L", DashboardViewModel.money(s.cyclePnL), tone: s.cyclePnL >= 0 ? .positive : .negative)
        }
    }

    private func risk(_ s: PropFirmStatusSnapshot) -> some View {
        section("Risk") {
            row("Drawdown floor", DashboardViewModel.money(s.drawdownFloor))
            row("Distance to DD", DashboardViewModel.money(s.distanceToDD), tone: s.distanceDanger ? .negative : .positive)
            if let limit = s.maxDrawdownLimit {
                row("Max drawdown", DashboardViewModel.money(limit))
            }
            row("Daily loss used", DashboardViewModel.money(s.dailyLossUsed), tone: s.dailyDrawdownBreached ? .negative : .neutral)
            if let daily = s.dailyLossLimit {
                row("Daily loss limit", DashboardViewModel.money(daily))
            } else {
                row("Daily loss limit", "Not set")
            }
            if s.dailyDrawdownBreached {
                Text("Daily drawdown rule breached for this cycle.")
                    .experienceStyle(.footnote, color: colors.loss)
            }
        }
    }

    private func targets(_ s: PropFirmStatusSnapshot) -> some View {
        section("Targets") {
            if let target = s.profitTarget, target > 0 {
                row("Profit target", DashboardViewModel.money(target))
                row("Progress", "\(Int(s.profitTargetProgress.rounded()))%")
                ProgressView(value: min(max(s.profitTargetProgress / 100, 0), 1))
                    .tint(s.isPassed ? colors.profit : colors.accent)
            } else {
                row("Profit target", "Not set")
            }
            if let required = s.winningDaysRequired, required > 0 {
                row("Winning days", "\(s.winningDays) / \(required)")
            } else {
                row("Winning days", "\(s.winningDays) (no minimum)")
            }
        }
    }

    private func consistency(_ s: PropFirmStatusSnapshot) -> some View {
        section("Consistency") {
            if s.consistencyRequired {
                row("Rule", "Biggest win ≤ consistency % of total wins")
                row("State", s.consistencyMet ? "Passing" : "Failing", tone: s.consistencyMet ? .positive : .negative)
            } else {
                Text("No consistency rule configured on this account.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }
        }
    }

    private func payouts(_ s: PropFirmStatusSnapshot) -> some View {
        section("Payouts") {
            if s.phaseLabel == "Funded" {
                row(
                    "Eligibility",
                    s.payoutReady ? "Ready" : "Not yet",
                    tone: s.payoutReady ? .positive : .neutral
                )
                Text("Payout readiness mirrors web `isPropfirmPayoutReady` (client advisory). Cycle history loads in a later pass.")
                    .experienceStyle(.caption2, color: colors.tertiaryText)
            } else {
                Text("Payout eligibility applies after the account is funded.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }
        }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text(title)
                .experienceStyle(.footnote, color: colors.tertiaryText)
                .textCase(.uppercase)
                .tracking(0.5)
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(ExperienceSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.fillSecondary.opacity(0.5), in: RoundedRectangle(
                cornerRadius: ExperienceRadius.md,
                style: .continuous
            ))
        }
    }

    private func row(
        _ label: String,
        _ value: String,
        tone: DashboardMetricTone = .neutral
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .experienceStyle(.callout, color: colors.secondaryText)
            Spacer()
            Text(value)
                .font(.system(.callout, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(toneColor(tone))
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 6)
    }

    private func toneColor(_ tone: DashboardMetricTone) -> Color {
        switch tone {
        case .neutral: return colors.primaryText
        case .positive: return colors.profit
        case .negative: return colors.loss
        }
    }
}
