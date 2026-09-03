import SwiftUI

struct CheckInDayDetailView: View {
    let dateKey: String
    let data: DataEnvironment
    let navigationCoordinator: NavigationCoordinator

    @State private var detail: CheckInDayDetail
    @State private var showsEditCheckIn = false

    @Environment(\.themeColors) private var colors

    init(dateKey: String, data: DataEnvironment, navigationCoordinator: NavigationCoordinator) {
        self.dateKey = dateKey
        self.data = data
        self.navigationCoordinator = navigationCoordinator
        _detail = State(initialValue: CheckInHistorySessionStore.shared.detail(for: dateKey))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                checkInSection
                performanceSection
                tradesSection
            }
            .padding(ExperienceSpacing.md)
        }
        .experienceScreenBackground()
        .experienceNavigationTitle(formattedTitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit Check-In") { showsEditCheckIn = true }
            }
        }
        .sheet(isPresented: $showsEditCheckIn) {
            NavigationStack {
                DailyCheckInView(
                    viewModel: DailyCheckInViewModel(
                        repository: data.dailyCheckIns,
                        session: data.session,
                        existing: detail.checkIn,
                        dateKey: dateKey
                    ),
                    onClose: {
                        detail = CheckInHistorySessionStore.shared.detail(for: dateKey)
                        showsEditCheckIn = false
                    }
                )
            }
            .experienceSheetChrome()
        }
        .accessibilityIdentifier("checkInDay.detail")
    }

    private var formattedTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        guard let date = formatter.date(from: dateKey) else { return dateKey }
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private var checkInSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Daily Check-In")
                .experienceStyle(.headline, color: colors.primaryText)

            if let checkIn = detail.checkIn {
                metricGrid([
                    ("Sleep", sleepText(checkIn.sleepHours)),
                    ("Sleep Quality", ratingText(checkIn.sleepQuality)),
                    ("Morning", ratingText(checkIn.morningRating)),
                    ("Stress", ratingText(checkIn.stressLevel)),
                    ("Energy", ratingText(checkIn.energyLevel)),
                    ("Focus", ratingText(checkIn.focusLevel)),
                ])
                if let notes = checkIn.notes, !notes.isEmpty {
                    Text(notes)
                        .experienceStyle(.footnote, color: colors.secondaryText)
                        .padding(.top, ExperienceSpacing.xs)
                }
            } else {
                Text("No check-in logged for this day.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }
        }
        .padding(ExperienceSpacing.md)
        .background(colors.surfacePrimary, in: RoundedRectangle(cornerRadius: ExperienceRadius.sm))
    }

    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Trading Performance")
                .experienceStyle(.headline, color: colors.primaryText)

            if detail.trades.isEmpty {
                Text("No trades on this day.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            } else {
                metricGrid([
                    ("P&L", TraderPsychologyAnalyticsEngine.money(detail.metrics.totalPnL)),
                    ("Trades", "\(detail.metrics.tradeCount)"),
                    ("Win Rate", TraderPsychologyAnalyticsEngine.formatWinRate(detail.metrics.winRate)),
                    ("Avg Trade", TraderPsychologyAnalyticsEngine.money(detail.metrics.averagePnL ?? 0)),
                    ("Profit Factor", detail.metrics.profitFactor.map {
                        String(format: "%.2f", NSDecimalNumber(decimal: $0).doubleValue)
                    } ?? "—"),
                ])
            }
        }
        .padding(ExperienceSpacing.md)
        .background(colors.surfacePrimary, in: RoundedRectangle(cornerRadius: ExperienceRadius.sm))
    }

    private var tradesSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Trades")
                .experienceStyle(.headline, color: colors.primaryText)

            ForEach(detail.trades) { trade in
                Button {
                    navigationCoordinator.pushHome(.tradeDetail(trade.id))
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(trade.symbol.ticker)
                                .experienceStyle(.subheadline, color: colors.primaryText)
                                .fontWeight(.semibold)
                            Text(trade.side == .long ? "Long" : "Short")
                                .experienceStyle(.caption, color: colors.tertiaryText)
                        }
                        Spacer()
                        Text(TraderPsychologyAnalyticsEngine.money(trade.realizedPnL?.amount ?? 0))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(
                                (trade.realizedPnL?.amount ?? 0) >= 0 ? colors.profit : colors.loss
                            )
                    }
                    .padding(ExperienceSpacing.md)
                    .background(colors.surfaceSecondary, in: RoundedRectangle(cornerRadius: ExperienceRadius.sm))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func metricGrid(_ rows: [(String, String)]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: ExperienceSpacing.sm) {
            ForEach(rows, id: \.0) { label, value in
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                    Text(value)
                        .experienceStyle(.subheadline, color: colors.primaryText)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func ratingText(_ value: Int?) -> String {
        guard let value else { return "—" }
        return "\(value)/5"
    }

    private func sleepText(_ hours: Decimal?) -> String {
        guard let hours else { return "—" }
        return String(format: "%.1fh", NSDecimalNumber(decimal: hours).doubleValue)
    }
}
