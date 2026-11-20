import SwiftUI

// MARK: - Section chrome

struct PropFirmDetailSectionHeader: View {
    let title: String
    var infoTitle: String?
    var infoBody: String?
    var infoAccessibilityID: String?

    var body: some View {
        AnalyticsSectionHeader(
            title: title,
            infoTitle: infoTitle,
            infoBody: infoBody,
            infoAccessibilityID: infoAccessibilityID
        )
        .padding(.horizontal, ExperienceSpacing.md)
    }
}

// MARK: - Summary

struct PropFirmDetailSummaryView: View {
    let snapshot: PropFirmStatusSnapshot
    let glanceLines: [PropFirmDetailPresentation.GlanceLine]
    var fundedPayoutActionTitle: String?
    var onFundedPayoutAction: (() -> Void)?

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.sm) {
                VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                    Text(primaryTitle)
                        .experienceStyle(.headline, color: colors.primaryText)
                    Text(subtitleLine)
                        .experienceStyle(.subheadline, color: colors.secondaryText)
                        .lineLimit(2)
                }
                Spacer(minLength: ExperienceSpacing.sm)
                statusBadge
            }

            Text(DashboardViewModel.money(snapshot.currentBalance))
                .font(.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(colors.primaryText)
                .accessibilityIdentifier("propFirm.summary.balance")

            HStack(alignment: .center, spacing: ExperienceSpacing.xs) {
                ExperienceTag(title: snapshot.phaseLabel, tone: .info)
                if snapshot.configuredAccountSize > 0 {
                    ExperienceTag(
                        title: NumberDisplay.money(snapshot.configuredAccountSize),
                        tone: .info
                    )
                }
                Spacer(minLength: ExperienceSpacing.sm)
                if let fundedPayoutActionTitle, let onFundedPayoutAction, snapshot.isFunded {
                    Button(action: onFundedPayoutAction) {
                        Text(fundedPayoutActionTitle)
                            .experienceStyle(.footnote, color: colors.accent)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.experiencePlain)
                    .accessibilityIdentifier("propFirm.summary.payouts")
                }
            }

            if !glanceLines.isEmpty {
                PropFirmDetailGlanceBanners(lines: glanceLines)
            }
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceDashboardCard(prominence: .featured)
        .padding(.horizontal, ExperienceSpacing.md)
        .accessibilityIdentifier("propFirm.summary")
    }

    private var primaryTitle: String {
        let firm = snapshot.firmName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !firm.isEmpty { return firm }
        return snapshot.accountName
    }

    private var subtitleLine: String {
        let firm = snapshot.firmName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !firm.isEmpty, firm != snapshot.accountName {
            return snapshot.accountName
        }
        return snapshot.statusLabel
    }

    private var statusBadge: some View {
        Text(snapshot.statusLabel)
            .font(.system(.caption2, design: .rounded).weight(.bold))
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(badgeColor.opacity(0.14), in: Capsule())
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var badgeColor: Color {
        switch snapshot.riskTone {
        case .positive: return colors.profit
        case .negative: return colors.loss
        case .neutral: return colors.accent
        }
    }
}

private struct PropFirmDetailGlanceBanners: View {
    let lines: [PropFirmDetailPresentation.GlanceLine]

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            ForEach(lines) { line in
                HStack(spacing: ExperienceSpacing.xs) {
                    Image(systemName: icon(for: line.tone))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(iconColor(for: line.tone))
                    Text(line.text)
                        .experienceStyle(.footnote, color: colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, ExperienceSpacing.sm)
                .padding(.vertical, ExperienceSpacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(colors.fillSecondary.opacity(0.55), in: RoundedRectangle(cornerRadius: ExperienceRadius.sm))
            }
        }
    }

    private func icon(for tone: PropFirmDetailPresentation.GlanceTone) -> String {
        switch tone {
        case .positive: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .neutral: return "info.circle.fill"
        }
    }

    private func iconColor(for tone: PropFirmDetailPresentation.GlanceTone) -> Color {
        switch tone {
        case .positive: return colors.profit
        case .warning: return colors.warning
        case .neutral: return colors.secondaryText
        }
    }
}

// MARK: - Progress & targets

struct PropFirmDetailProgressPanel: View {
    let snapshot: PropFirmStatusSnapshot
    let contentPlan: PropFirmDetailContentPlan

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            PropFirmDetailSectionHeader(title: snapshot.isFunded ? "Cycle targets" : "Evaluation")

            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                if let target = snapshot.profitTarget, target > 0 {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Profit target")
                            .experienceStyle(.subheadline, color: colors.secondaryText)
                        Spacer(minLength: 8)
                        Text(DashboardViewModel.money(target))
                            .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                        if let pct = PropFirmDetailPresentation.formattedPercentOfAccount(
                            amount: target,
                            accountSize: snapshot.configuredAccountSize
                        ) {
                            Text(pct)
                                .experienceStyle(.caption, color: colors.tertiaryText)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Progress")
                                .experienceStyle(.caption2, color: colors.tertiaryText)
                            Spacer()
                            Text("\(Int(snapshot.profitTargetProgress.rounded()))%")
                                .font(.system(.caption2, design: .rounded).weight(.semibold).monospacedDigit())
                        }
                        ProgressView(value: min(max(snapshot.profitTargetProgress / 100, 0), 1))
                            .tint(snapshot.isPassed ? colors.profit : colors.accent)
                    }
                }

                if let required = snapshot.winningDaysRequired, required > 0 {
                    HStack {
                        Text("Winning days")
                            .experienceStyle(.subheadline, color: colors.secondaryText)
                        Spacer()
                        Text("\(snapshot.winningDays)/\(required)")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                        Image(systemName: snapshot.winningDaysTargetMet ? "checkmark.circle.fill" : "clock")
                            .foregroundStyle(snapshot.winningDaysTargetMet ? colors.profit : colors.secondaryText)
                    }
                }
            }
            .padding(ExperienceSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .experienceDashboardCard(prominence: .standard)
            .padding(.horizontal, ExperienceSpacing.md)
        }
        .accessibilityIdentifier("propFirm.progress")
    }
}

// MARK: - Drawdown

struct PropFirmDetailDrawdownPanel: View {
    let snapshot: PropFirmStatusSnapshot
    let contentPlan: PropFirmDetailContentPlan

    @Environment(\.themeColors) private var colors
    @State private var showsBalanceDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            PropFirmDetailSectionHeader(
                title: "Drawdown",
                infoTitle: "Drawdown",
                infoBody: contentPlan.drawdownInfoBody(),
                infoAccessibilityID: "propFirm.drawdown.info"
            )

            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Distance to floor")
                            .experienceStyle(.caption2, color: colors.tertiaryText)
                        Text(DashboardViewModel.money(snapshot.distanceToDD))
                            .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                            .foregroundStyle(cushionTone)
                    }
                    Spacer(minLength: ExperienceSpacing.md)
                    if let limit = snapshot.maxDrawdownLimit, limit > 0 {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("DD used")
                                .experienceStyle(.caption2, color: colors.tertiaryText)
                            Text(DashboardViewModel.money(snapshot.maxDrawdownUsed))
                                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                        }
                    }
                }

                if let type = snapshot.drawdownType {
                    Text(PropFirmDetailPresentation.drawdownTypeLabel(type))
                        .experienceStyle(.caption, color: colors.secondaryText)
                }

                drawdownBar

                Button {
                    withAnimation(ExperienceMotion.navigation) {
                        showsBalanceDetails.toggle()
                    }
                } label: {
                    HStack {
                        Text(showsBalanceDetails ? "Hide balance details" : "Balance details")
                            .experienceStyle(.footnote, color: colors.accent)
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: showsBalanceDetails ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(colors.tertiaryText)
                    }
                }
                .buttonStyle(.experiencePlain)

                if showsBalanceDetails {
                    balanceDetailRows
                }
            }
            .padding(ExperienceSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .experienceDashboardCard(prominence: .standard)
            .padding(.horizontal, ExperienceSpacing.md)
        }
        .accessibilityIdentifier("propFirm.drawdown")
    }

    private var cushionTone: Color {
        if snapshot.isFailed || snapshot.distanceToDD < 0 { return colors.loss }
        if snapshot.distanceDanger { return colors.warning }
        return colors.profit
    }

    @ViewBuilder
    private var drawdownBar: some View {
        let low = min(snapshot.drawdownFloor, snapshot.cycleStartBalance)
        let high = max(snapshot.peakBalance, snapshot.currentBalance, low + 1)
        let span = max(high - low, 1)
        let floorRatio = NSDecimalNumber(decimal: (snapshot.drawdownFloor - low) / span).doubleValue
        let balanceRatio = NSDecimalNumber(decimal: (snapshot.currentBalance - low) / span).doubleValue
        let floorClamped = min(max(floorRatio, 0), 1)
        let balanceClamped = min(max(balanceRatio, 0), 1)

        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(colors.fillSecondary.opacity(0.8))
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(colors.accent.opacity(0.35))
                        .frame(width: geo.size.width * balanceClamped)
                    Rectangle()
                        .fill(colors.warning.opacity(0.9))
                        .frame(width: 2)
                        .offset(x: geo.size.width * floorClamped - 1)
                }
            }
            .frame(height: 8)
            HStack {
                Text("Floor")
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                Spacer()
                Text("Peak")
                    .experienceStyle(.caption2, color: colors.tertiaryText)
            }
        }
    }

    private var balanceDetailRows: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            balanceRow("Cycle start", snapshot.cycleStartBalance)
            balanceRow("Peak", snapshot.peakBalance)
            balanceRow("Floor", snapshot.drawdownFloor, emphasis: true)
            balanceRow("Current", snapshot.currentBalance)
            if let limit = snapshot.maxDrawdownLimit, limit > 0 {
                balanceRow("Max limit", limit)
            }
        }
        .padding(.top, ExperienceSpacing.xs)
    }

    private func balanceRow(_ label: String, _ amount: Decimal, emphasis: Bool = false) -> some View {
        HStack {
            Text(label)
                .experienceStyle(.callout, color: colors.secondaryText)
            Spacer()
            Text(DashboardViewModel.money(amount))
                .font(.system(.callout, design: .rounded).weight(emphasis ? .bold : .semibold).monospacedDigit())
                .foregroundStyle(emphasis ? colors.warning : colors.primaryText)
        }
    }
}

// MARK: - Rule rows

struct PropFirmRuleRow: Hashable {
    enum Status: Hashable {
        case met
        case pending
        case violation
        case neutral
    }

    var topic: PropFirmDetailRuleTopic
    var icon: String
    var label: String
    var value: String
    var status: Status
}

struct PropFirmRuleRowView: View {
    let row: PropFirmRuleRow
    var infoBody: String?

    @Environment(\.themeColors) private var colors
    @State private var showsInfo = false

    var body: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            Image(systemName: row.icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(colors.secondaryText)
                .frame(width: 22)
            Text(row.label)
                .experienceStyle(.callout, color: colors.secondaryText)
            if let infoBody {
                Button {
                    showsInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(colors.tertiaryText)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showsInfo) {
                    VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                        Text(row.label)
                            .font(ExperienceTypography.subheadline.weight(.semibold))
                        Text(infoBody)
                            .font(ExperienceTypography.footnote)
                            .foregroundStyle(colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(ExperienceSpacing.md)
                    .frame(width: 280, alignment: .leading)
                    .experienceAnalyticsPopoverChrome()
                }
            }
            Spacer(minLength: 8)
            Text(row.value)
                .font(.system(.callout, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(colors.primaryText)
            statusIcon
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch row.status {
        case .met:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(colors.profit)
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(colors.secondaryText)
        case .violation:
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(colors.loss)
        case .neutral:
            EmptyView()
        }
    }
}

struct PropFirmDetailTradingRulesPanel: View {
    let snapshot: PropFirmStatusSnapshot
    let contentPlan: PropFirmDetailContentPlan

    @Environment(\.themeColors) private var colors

    var body: some View {
        let rows = contentPlan.tradingRuleRows()
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                PropFirmDetailSectionHeader(title: "Trading rules")

                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        PropFirmRuleRowView(
                            row: row,
                            infoBody: infoBody(for: row.topic)
                        )
                        if index < rows.count - 1 {
                            Divider().opacity(0.35)
                        }
                    }
                }
                .padding(ExperienceSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .experienceDashboardCard(prominence: .standard)
                .padding(.horizontal, ExperienceSpacing.md)
            }
            .accessibilityIdentifier("propFirm.rules")
        }
    }

    private func infoBody(for topic: PropFirmDetailRuleTopic) -> String? {
        switch topic {
        case .consistencyRule:
            return contentPlan.consistencyInfoBody()
        case .winningDayThreshold, .winningDayThresholdExplanation:
            return contentPlan.winningDayThresholdInfoBody()
        default:
            return nil
        }
    }
}

// MARK: - Payouts (dedicated page)

struct PropFirmAccountPayoutsView: View {
    @State private var viewModel: PropFirmDetailViewModel
    @State private var showsRecordPayout = false

    private let data: DataEnvironment
    private let navigationCoordinator: NavigationCoordinator

    @Environment(\.themeColors) private var colors

    init(
        accountID: TradingAccountID,
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator
    ) {
        self.data = data
        self.navigationCoordinator = navigationCoordinator
        _viewModel = State(
            initialValue: PropFirmDetailViewModel(
                accountID: accountID,
                trades: data.trades,
                session: data.session,
                detailCache: data.detailCache,
                rpc: data.rpc,
                realtimeHub: data.realtimeHub,
                navigationCoordinator: navigationCoordinator
            )
        )
    }

    var body: some View {
        Group {
            if let snapshot = viewModel.snapshot, snapshot.isFunded {
                let contentPlan = PropFirmDetailContentPlan(snapshot: snapshot)
                ScrollView {
                    PropFirmDetailPayoutsPanel(
                        snapshot: snapshot,
                        contentPlan: contentPlan,
                        onRecordPayout: { showsRecordPayout = true },
                        recordPayoutEnabled: true
                    )
                    .padding(.vertical, ExperienceSpacing.md)
                }
            } else if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ExperienceEmptyState(
                    icon: .chart,
                    title: "Payouts unavailable",
                    message: viewModel.errorMessage ?? "This account is not in funded mode."
                )
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Payouts")
        .task { await viewModel.loadIfNeeded() }
        .refreshable { await viewModel.refresh() }
        .onChange(of: TradeJournalMutationStore.shared.revision) { _, _ in
            Task { await viewModel.refresh() }
        }
        .onChange(of: AccountMutationStore.shared.revision) { _, _ in
            Task { await viewModel.refresh() }
        }
        .sheet(isPresented: $showsRecordPayout, onDismiss: {
            Task { await viewModel.refresh() }
        }) {
            RecordPayoutFlowView(
                accountID: viewModel.accountID,
                data: data,
                navigationCoordinator: navigationCoordinator,
                onWithdrawalFlowComplete: {
                    Task { await viewModel.refresh() }
                }
            )
        }
        .accessibilityIdentifier("propFirm.payoutsPage")
    }
}

struct PropFirmDetailPayoutsPanel: View {
    let snapshot: PropFirmStatusSnapshot
    let contentPlan: PropFirmDetailContentPlan
    var onRecordPayout: () -> Void
    var recordPayoutEnabled: Bool

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            PropFirmDetailSectionHeader(
                title: "Payouts",
                infoTitle: "Payout drawdown",
                infoBody: contentPlan.payoutBehaviorInfoBody(),
                infoAccessibilityID: "propFirm.payouts.info"
            )

            VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Eligibility")
                            .experienceStyle(.caption2, color: colors.tertiaryText)
                        Text(snapshot.payoutReady ? "Ready" : "Not yet")
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .foregroundStyle(snapshot.payoutReady ? colors.profit : colors.primaryText)
                    }
                    Spacer()
                    if let behavior = PropFirmDetailPresentation.payoutDrawdownBehaviorTitle(
                        snapshot.payoutDrawdownBehaviorRaw
                    ) {
                        ExperienceTag(title: behavior, tone: .info)
                    }
                }

                if snapshot.supportsRecordPayout {
                    Button(action: onRecordPayout) {
                        Label("Record Payout", systemImage: "dollarsign.circle")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!recordPayoutEnabled)
                    .accessibilityIdentifier("propFirm.recordPayout")
                }

                FundedPayoutCycleHistoryContent(cycles: snapshot.completedPayoutHistory)
            }
            .padding(ExperienceSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .experienceDashboardCard(prominence: .featured)
            .padding(.horizontal, ExperienceSpacing.md)
        }
        .accessibilityIdentifier("propFirm.payouts")
    }
}