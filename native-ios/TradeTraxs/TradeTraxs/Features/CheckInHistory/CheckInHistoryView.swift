import SwiftUI

struct CheckInHistoryView: View {
    @State private var viewModel: CheckInHistoryViewModel

    @Environment(\.themeColors) private var colors

    init(data: DataEnvironment, navigationCoordinator: NavigationCoordinator) {
        _viewModel = State(
            initialValue: CheckInHistoryViewModel(
                dailyCheckIns: data.dailyCheckIns,
                trades: data.trades,
                session: data.session,
                detailCache: data.detailCache,
                navigationCoordinator: navigationCoordinator
            )
        )
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .loading where viewModel.summaries.isEmpty:
                ProgressView("Loading history…")
            case .failed(let message):
                ExperienceErrorState(title: "Couldn't load history", message: message) {
                    Task { await viewModel.refresh() }
                }
            default:
                listContent
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Check-In History")
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.bootstrapIfNeeded() }
        .accessibilityIdentifier("checkInHistory.list")
    }

    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: ExperienceSpacing.sm) {
                if viewModel.summaries.isEmpty {
                    ExperienceEmptyState(
                        icon: .calendar,
                        title: "No history yet",
                        message: "Log daily check-ins and trades to build your history."
                    )
                    .padding(.top, ExperienceSpacing.xxl)
                } else {
                    ForEach(viewModel.summaries) { day in
                        Button { viewModel.openDay(day) } label: {
                            CheckInHistoryDayRow(summary: day)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(ExperienceSpacing.md)
        }
    }
}

struct CheckInHistoryDayRow: View {
    let summary: CheckInHistoryDaySummary

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text(formattedDate(summary.dateKey))
                .experienceStyle(.headline, color: colors.primaryText)

            if let line = checkInLine {
                Text(line)
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }

            if summary.hasTrades {
                Text(tradeLine)
                    .experienceStyle(.footnote, color: colors.secondaryText)
            } else if !summary.hasCheckIn {
                Text("No check-in or trades")
                    .experienceStyle(.footnote, color: colors.tertiaryText)
            }
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfacePrimary, in: RoundedRectangle(cornerRadius: ExperienceRadius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                .stroke(colors.border, lineWidth: 1)
        }
    }

    private var checkInLine: String? {
        guard let checkIn = summary.checkIn else { return nil }
        var parts: [String] = []
        if let hours = checkIn.sleepHours {
            parts.append(String(format: "%.1fh Sleep", NSDecimalNumber(decimal: hours).doubleValue))
        }
        if let focus = checkIn.focusLevel {
            parts.append("Focus \(focus)/5")
        }
        if let stress = checkIn.stressLevel {
            parts.append("Stress \(TraderDailyCheckInStressScale.displayText(for: stress))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private var tradeLine: String {
        var parts: [String] = []
        let pnl = summary.totalPnL
        parts.append("\(pnl >= 0 ? "+" : "")\(TraderPsychologyAnalyticsEngine.money(pnl)) P&L")
        parts.append("\(summary.tradeCount) Trades")
        if let rate = summary.winRate {
            parts.append(TraderPsychologyAnalyticsEngine.formatWinRate(rate) + " Win")
        }
        return parts.joined(separator: " • ")
    }

    private func formattedDate(_ key: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        guard let date = formatter.date(from: key) else { return key }
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
