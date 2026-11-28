import SwiftUI

struct CheckInHistoryView: View {
    @State private var viewModel: CheckInHistoryViewModel
    @State private var contentFilter: CheckInHistoryContentFilter = .all

    @Environment(\.themeColors) private var colors
    @Environment(\.traxsProPreviewReadOnly) private var traxsProPreviewReadOnly

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
                ExperienceLoadingSpinner(message: "Loading history…")
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
        .safeAreaInset(edge: .top, spacing: 0) {
            if PsychologyAnalyticsPreviewSupport.usesSampleCheckInHistory || traxsProPreviewReadOnly {
                checkInHistorySampleBanner
            }
        }
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.bootstrapIfNeeded() }
        .accessibilityIdentifier("checkInHistory.list")
    }

    private var checkInHistorySampleBanner: some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.caption.weight(.semibold))
                .foregroundStyle(colors.accent)
            Text(MonetizationPlanCopy.psychologyAnalyticsPreviewHistoryListSubtitle)
                .experienceStyle(.caption, color: colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.vertical, ExperienceSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfacePrimary)
        .overlay(alignment: .bottom) {
            colors.separator.frame(height: ExperienceBorder.hairline)
        }
        .accessibilityIdentifier("checkInHistory.sampleBanner")
    }

    private var filteredSummaries: [CheckInHistoryDaySummary] {
        viewModel.summaries.filter { $0.matches(contentFilter: contentFilter) }
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
                    .experienceScrollEmbeddedSectionFill(minHeight: 360)
                    .padding(.top, ExperienceSpacing.lg)
                } else {
                    Picker("History filter", selection: $contentFilter) {
                        ForEach(CheckInHistoryContentFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("checkInHistory.contentFilter")

                    if filteredSummaries.isEmpty {
                        ExperienceEmptyState(
                            icon: .calendar,
                            title: emptyFilterTitle,
                            message: emptyFilterMessage
                        )
                        .experienceScrollEmbeddedSectionFill(minHeight: 280)
                        .padding(.top, ExperienceSpacing.md)
                    } else {
                        ForEach(filteredSummaries) { day in
                            Button { viewModel.openDay(day) } label: {
                                CheckInHistoryDayRow(summary: day, contentFilter: contentFilter)
                            }
                            .buttonStyle(.experiencePlain)
                        }
                    }
                }
            }
            .padding(ExperienceSpacing.md)
        }
    }

    private var emptyFilterTitle: String {
        switch contentFilter {
        case .all: return "No history yet"
        case .trades: return "No trade days"
        case .psychology: return "No check-in days"
        }
    }

    private var emptyFilterMessage: String {
        switch contentFilter {
        case .all:
            return "Log daily check-ins and trades to build your history."
        case .trades:
            return "No days with trades in this window. Try All or Psychology."
        case .psychology:
            return "No days with a daily check-in in this window. Try All or Trades."
        }
    }
}

struct CheckInHistoryDayRow: View {
    let summary: CheckInHistoryDaySummary
    var contentFilter: CheckInHistoryContentFilter = .all

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text(formattedDate(summary.dateKey))
                .experienceStyle(.headline, color: colors.primaryText)

            switch contentFilter {
            case .all:
                if let line = legacyCheckInPreviewLine {
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
            case .trades:
                Text(tradeLine)
                    .experienceStyle(.footnote, color: colors.secondaryText)
            case .psychology:
                if let line = psychologyPreviewLine {
                    Text(line)
                        .experienceStyle(.footnote, color: colors.secondaryText)
                }
            }
        }
        .checkInHistorySectionCard(style: .listRow)
    }

    /// Unchanged All-tab preview (sleep, focus, stress).
    private var legacyCheckInPreviewLine: String? {
        guard let checkIn = summary.checkIn else { return nil }
        var parts: [String] = []
        if let hours = checkIn.sleepHours {
            parts.append("\(NumberDisplay.hours(NSDecimalNumber(decimal: hours).doubleValue)) Sleep")
        }
        if let focus = checkIn.focusLevel {
            parts.append("Focus \(focus)/5")
        }
        if let stress = checkIn.stressLevel {
            parts.append("Stress \(TraderDailyCheckInStressScale.displayText(for: stress))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private var psychologyPreviewLine: String? {
        guard let checkIn = summary.checkIn else { return nil }
        let parts = CheckInHistoryFieldClassification.psychologyPreviewParts(for: checkIn)
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
