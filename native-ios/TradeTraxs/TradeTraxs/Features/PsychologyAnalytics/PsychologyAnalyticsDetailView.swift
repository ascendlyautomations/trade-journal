import SwiftUI

/// Holds the latest psychology analytics report for dashboard → detail navigation.
@MainActor
final class PsychologyAnalyticsSessionStore {
    static let shared = PsychologyAnalyticsSessionStore()

    private(set) var report: PsychologyAnalyticsReport?
    private(set) var unlockProgress: PsychologyInsightsUnlockProgress = .zero
    private(set) var postUnlockGapMessages: [String] = []
    private(set) var displayInsightCards: [PsychologyInsightCard] = []
    private(set) var profileID: ProfileID?
    private(set) var scopeFingerprint: String?
    private(set) var scopeLabel: String?
    private(set) var contentRevision = 0
    var highlightedSectionID: String?

    private init() {}

    func update(
        report: PsychologyAnalyticsReport?,
        unlockProgress: PsychologyInsightsUnlockProgress,
        postUnlockGapMessages: [String],
        displayInsightCards: [PsychologyInsightCard] = [],
        profileID: ProfileID?,
        scopeFingerprint: String?,
        scopeLabel: String? = nil
    ) {
        self.report = report
        self.unlockProgress = unlockProgress
        self.postUnlockGapMessages = postUnlockGapMessages
        self.displayInsightCards = displayInsightCards
        self.profileID = profileID
        self.scopeFingerprint = scopeFingerprint
        self.scopeLabel = scopeLabel
        contentRevision += 1
    }

    func clearSession() {
        update(
            report: nil,
            unlockProgress: .zero,
            postUnlockGapMessages: [],
            profileID: nil,
            scopeFingerprint: nil,
            scopeLabel: nil
        )
    }

    func clearIfProfileMismatch(_ profileID: ProfileID) {
        guard let current = self.profileID, current != profileID else { return }
        clearSession()
    }

    func matchesCachedPresentation(profileID: ProfileID, scopeFingerprint: String) -> Bool {
        self.profileID == profileID && self.scopeFingerprint == scopeFingerprint
    }

    func focusSection(_ sectionID: String?) {
        highlightedSectionID = sectionID
    }
}

struct PsychologyAnalyticsDetailView: View {
    let report: PsychologyAnalyticsReport
    var insightCards: [PsychologyInsightCard] = []
    var unlockProgress: PsychologyInsightsUnlockProgress = .zero
    var postUnlockGapMessages: [String] = []
    var highlightedSectionID: String?
    var onOpenCoach: (() -> Void)?
    var onOpenCheckInHistory: (() -> Void)?
    var onOpenCheckInHistoryDay: ((CheckInHistoryDaySummary) -> Void)?
    var freePreviewHistorySummaries: [CheckInHistoryDaySummary] = []
    var injectedCoachSummary: PsychologyCoachSummary? = nil
    var showsSamplePreviewBanner = false
    var showsPreviewUpgradeFooter = false
    var navigationCoordinator: NavigationCoordinator?
    var preferences: (any TradingPreferencesRepository)?
    var viewerID: ProfileID?
    var detailCache: DetailPresentationCache?

    @Environment(\.themeColors) private var colors
    @State private var advancedExpanded = false

    private static let advancedSectionIDs: Set<String> = [
        "sleep", "mentalState", "conviction", "discipline", "emotion",
        "afterLosses", "tradeFrequency", "combined"
    ]

    private var showsFreePreviewOnlyContent: Bool {
        !freePreviewHistorySummaries.isEmpty
    }

    private var resolvedCoachSummary: PsychologyCoachSummary? {
        injectedCoachSummary ?? PsychologyCoachSessionStore.shared.deterministicSummary
    }

    /// Sample preview presents the paywall in-place; Pro navigates to Psychology Coach.
    private var openPsychologyCoachAction: (() -> Void)? {
        if showsPreviewUpgradeFooter {
            return {
                ExperienceHaptics.play(.selection)
                ProUpgradeCoordinator.shared.present(reason: .feature(.premiumAnalytics))
            }
        }
        return onOpenCoach
    }

    private var advancedSections: [PsychologyAnalyticsSection] {
        report.sections.filter { Self.advancedSectionIDs.contains($0.id) }
    }

    private var resolvedInsightCards: [PsychologyInsightCard] {
        if !insightCards.isEmpty { return insightCards }
        return report.dashboardCards
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                    if showsSamplePreviewBanner {
                        samplePreviewBanner
                    }
                    if let navigationCoordinator {
                        TradingPreferenceDiscoverySlot(
                            surface: .analytics,
                            userID: viewerID,
                            repository: preferences,
                            localHasTrade: report.baseline.tradeCount > 0,
                            navigationCoordinator: navigationCoordinator
                        )
                    }
                    overviewSection

                    if !freePreviewHistorySummaries.isEmpty {
                        freePreviewHistorySection
                    }

                    if !showsFreePreviewOnlyContent, navigationCoordinator != nil {
                        tradingRulesAnalyticsLink
                            .padding(.horizontal, ExperienceSpacing.md)
                    }

                    if !showsFreePreviewOnlyContent {
                        if !resolvedInsightCards.isEmpty {
                            comparisonInsightsSection
                        } else {
                            noMatchedDaysInsightSection
                        }
                    }

                    if !showsFreePreviewOnlyContent, !advancedSections.isEmpty {
                        advancedAnalyticsSection
                    }

                    if !showsFreePreviewOnlyContent,
                       let coachSummary = resolvedCoachSummary,
                       !coachSummary.recommendations.isEmpty {
                        PsychologySummarySection(
                            summary: coachSummary,
                            onOpenCoach: openPsychologyCoachAction,
                            recommendationsOnly: true
                        )
                        .padding(.horizontal, ExperienceSpacing.md)
                    }

                    if showsPreviewUpgradeFooter {
                        PsychologyAnalyticsPremiumLockedSection(includePreviewAction: false)
                            .padding(.horizontal, ExperienceSpacing.md)
                    }
                }
                .padding(.vertical, ExperienceSpacing.md)
            }
            .onAppear {
                guard let highlightedSectionID else { return }
                if Self.advancedSectionIDs.contains(highlightedSectionID) {
                    advancedExpanded = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation {
                        proxy.scrollTo(highlightedSectionID, anchor: .top)
                    }
                }
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Psychology Analytics")
        .toolbar {
            if openPsychologyCoachAction != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        ExperienceHaptics.play(.selection)
                        openPsychologyCoachAction?()
                    } label: {
                        Image(systemName: "brain.head.profile")
                    }
                    .accessibilityLabel("Psychology Coach")
                    .accessibilityIdentifier("psychologyAnalytics.psychologyCoach")
                }
            }
        }
        .accessibilityIdentifier("psychologyAnalytics.detail")
    }

    private var tradingRulesAnalyticsLink: some View {
        Button {
            navigationCoordinator?.pushTradingRulesAnalytics()
        } label: {
            HStack(spacing: ExperienceSpacing.sm) {
                VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                    Text("Trading Rules Analytics")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(colors.primaryText)
                    Text("Compliance score, violations, trends, and rule impact")
                        .experienceStyle(.caption, color: colors.secondaryText)
                }
                Spacer(minLength: ExperienceSpacing.sm)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(colors.tertiaryText)
            }
            .padding(ExperienceSpacing.md)
            .modifier(
                PsychologyAnalyticsOverviewCardChrome(
                    cornerRadius: ExperienceRadius.lg,
                    darkFill: colors.elevatedSurface
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("psychologyAnalytics.openTradingRules")
    }

    private var samplePreviewBanner: some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colors.accent)
            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                Text("Sample data preview")
                    .experienceStyle(.subheadline, color: colors.primaryText)
                    .fontWeight(.semibold)
                Text(MonetizationPlanCopy.psychologyAnalyticsPreviewSampleDataNote)
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceDashboardCard(cornerRadius: ExperienceRadius.md)
        .padding(.horizontal, ExperienceSpacing.md)
        .accessibilityIdentifier("psychologyAnalytics.sampleDataBanner")
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Overview")
                    .experienceStyle(.headline, color: colors.primaryText)
                Spacer(minLength: ExperienceSpacing.sm)
                if let onOpenCheckInHistory {
                    Button(action: onOpenCheckInHistory) {
                        HStack(spacing: ExperienceSpacing.xxs) {
                            ExperienceIcon(icon: .calendar, size: .sm, color: colors.accent)
                            Text("History")
                                .experienceStyle(.footnote, color: colors.accent)
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, ExperienceSpacing.sm)
                        .padding(.vertical, ExperienceSpacing.xs)
                        .experienceFilterChipRect(cornerRadius: ExperienceRadius.md)
                    }
                    .buttonStyle(.experiencePlain)
                    .accessibilityLabel("Check-In History")
                    .accessibilityIdentifier("psychologyAnalytics.checkInHistory")
                }
            }
            .padding(.horizontal, ExperienceSpacing.md)

            HStack(spacing: ExperienceSpacing.xs) {
                countTile(
                    value: unlockProgress.tradingDayCheckInCount,
                    label: "Check-in days"
                )
                countTile(value: report.baseline.tradeCount, label: "Qualifying trades")
                countTile(value: report.matchedDayCount, label: "Matched days")
            }
            .padding(.horizontal, ExperienceSpacing.md)

            if report.baseline.tradeCount > 0 {
                VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                    Text("Your trades in this scope")
                        .experienceStyle(.caption, color: colors.tertiaryText)
                        .fontWeight(.semibold)
                    HStack(spacing: ExperienceSpacing.md) {
                        if report.baseline.winRate != nil {
                            metricPill(
                                "Win rate",
                                value: TraderPsychologyAnalyticsEngine.formatWinRate(report.baseline.winRate)
                            )
                        }
                        if report.baseline.tradeCount >= 5,
                           let average = TraderPsychologyAnalyticsEngine.optionalMoney(report.baseline.averagePnL) {
                            metricPill("Avg P&L / trade", value: average)
                        }
                    }
                }
                .padding(ExperienceSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .experienceDashboardCard(cornerRadius: ExperienceRadius.sm)
                .padding(.horizontal, ExperienceSpacing.md)
            }
        }
        .accessibilityIdentifier("psychologyAnalytics.overview")
    }

    private var freePreviewHistorySection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("History")
                    .experienceStyle(.headline, color: colors.primaryText)
                Spacer(minLength: ExperienceSpacing.sm)
                if let onOpenCheckInHistory {
                    Button(action: onOpenCheckInHistory) {
                        Text("See all")
                            .experienceStyle(.footnote, color: colors.accent)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.experiencePlain)
                    .accessibilityIdentifier("psychologyAnalytics.history.seeAll")
                }
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .accessibilityAddTraits(.isHeader)

            Text(MonetizationPlanCopy.psychologyAnalyticsFreePreviewHistorySubtitle)
                .experienceStyle(.caption, color: colors.tertiaryText)
                .padding(.horizontal, ExperienceSpacing.md)

            VStack(spacing: ExperienceSpacing.xs) {
                ForEach(freePreviewHistorySummaries) { day in
                    if let onOpenCheckInHistoryDay = onOpenCheckInHistoryDay {
                        Button {
                            onOpenCheckInHistoryDay(day)
                        } label: {
                            CheckInHistoryDayRow(summary: day, contentFilter: .psychology)
                        }
                        .buttonStyle(.experiencePlain)
                    } else {
                        CheckInHistoryDayRow(summary: day, contentFilter: .psychology)
                    }
                }
            }
            .padding(.horizontal, ExperienceSpacing.md)
        }
        .accessibilityIdentifier("psychologyAnalytics.history.preview")
    }

    private var comparisonInsightsSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Insights")
                .experienceStyle(.headline, color: colors.primaryText)
            Text(
                GeneratedProseNormalizer.normalize(
                    "Patterns from matched check-in days and trade psychology tags. Association only, not causation."
                )
            )
            .experienceStyle(.caption, color: colors.tertiaryText)

            VStack(spacing: ExperienceSpacing.xs) {
                ForEach(resolvedInsightCards) { card in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.displayHeadline)
                            .experienceStyle(.subheadline, color: colors.primaryText)
                            .fontWeight(.semibold)
                        Text(card.displayDetail)
                            .experienceStyle(.footnote, color: colors.secondaryText)
                    }
                    .padding(ExperienceSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .experienceDashboardCard(cornerRadius: ExperienceRadius.sm)
                }
            }
        }
        .padding(.horizontal, ExperienceSpacing.md)
    }

    private var noMatchedDaysInsightSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("No insight yet")
                .experienceStyle(.subheadline, color: colors.primaryText)
                .fontWeight(.semibold)
            Text(
                "A comparison appears after each side has at least 8 trades and a real difference in results."
            )
            .experienceStyle(.caption, color: colors.secondaryText)
            if !postUnlockGapMessages.isEmpty {
                ForEach(postUnlockGapMessages, id: \.self) { message in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                        Text(GeneratedProseNormalizer.normalize(message))
                            .experienceStyle(.caption, color: colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceDashboardCard(cornerRadius: ExperienceRadius.sm)
        .padding(.horizontal, ExperienceSpacing.md)
        .accessibilityIdentifier("psychologyAnalytics.insightGaps")
    }

    private var advancedAnalyticsSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Button {
                advancedExpanded.toggle()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Advanced analytics")
                            .experienceStyle(.subheadline, color: colors.primaryText)
                            .fontWeight(.semibold)
                        Text("Both sides of each comparison")
                            .experienceStyle(.caption, color: colors.tertiaryText)
                    }
                    Spacer(minLength: 0)
                    Text(advancedExpanded ? "Hide" : "Show")
                        .experienceStyle(.footnote, color: colors.accent)
                        .fontWeight(.semibold)
                }
                .padding(ExperienceSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .experienceDashboardCard(cornerRadius: ExperienceRadius.sm)
            }
            .buttonStyle(.experiencePlain)
            .padding(.horizontal, ExperienceSpacing.md)
            .accessibilityIdentifier("psychologyAnalytics.advancedToggle")

            if advancedExpanded {
                ForEach(advancedSections) { section in
                    sectionView(section)
                        .id(section.id)
                }
            }
        }
    }

    private func countTile(value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(colors.primaryText)
            Text(label)
                .experienceStyle(.caption2, color: colors.tertiaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ExperienceSpacing.sm)
        .modifier(PsychologyAnalyticsOverviewCardChrome(cornerRadius: ExperienceRadius.sm))
    }

    private func sectionView(_ section: PsychologyAnalyticsSection) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                Text(section.title)
                    .experienceStyle(.headline, color: colors.primaryText)
                if let subtitle = section.subtitle {
                    Text(subtitle)
                        .experienceStyle(.footnote, color: colors.tertiaryText)
                }
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .accessibilityAddTraits(.isHeader)

            if section.groups.isEmpty, let footnote = section.footnote {
                Text(footnote)
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .padding(.horizontal, ExperienceSpacing.md)
            } else {
                VStack(spacing: ExperienceSpacing.xs) {
                    ForEach(section.groups) { row in
                        metricsRow(row)
                    }
                }
                .padding(.horizontal, ExperienceSpacing.md)
            }

            if let footnote = section.footnote, !section.groups.isEmpty {
                Text(footnote)
                    .experienceStyle(.caption, color: colors.tertiaryText)
                    .padding(.horizontal, ExperienceSpacing.md)
            }
        }
    }

    private func metricsRow(_ row: PsychologyAnalyticsGroupRow) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text(row.label)
                .experienceStyle(.subheadline, color: colors.primaryText)
                .fontWeight(.semibold)

            if row.metrics.tradeCount >= 5 {
                HStack(spacing: ExperienceSpacing.md) {
                    if row.metrics.winRate != nil {
                        metricPill("Win rate", value: TraderPsychologyAnalyticsEngine.formatWinRate(row.metrics.winRate))
                    }
                    if let average = TraderPsychologyAnalyticsEngine.optionalMoney(row.metrics.averagePnL) {
                        metricPill("Avg P&L", value: average)
                    }
                }
            }
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            row.highlight ? colors.accent.opacity(0.08) : colors.surfacePrimary,
            in: RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                .stroke(colors.border, lineWidth: 1)
        }
    }

    private func metricPill(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .experienceStyle(.caption2, color: colors.tertiaryText)
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(colors.primaryText)
        }
    }
}

/// Light mode uses white overview tiles; dark mode keeps nested / elevated fills.
private struct PsychologyAnalyticsOverviewCardChrome: ViewModifier {
    @Environment(\.themeColors) private var colors
    @Environment(\.colorScheme) private var colorScheme

    var cornerRadius: CGFloat
    var darkFill: Color?

    func body(content: Content) -> some View {
        if colorScheme == .light {
            content
                .background(
                    colors.surfacePrimary,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            colors.border.opacity(ExperienceDashboardSurface.LightChrome.borderOpacity),
                            lineWidth: ExperienceBorder.hairline
                        )
                }
        } else if let darkFill {
            content.background(
                darkFill,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            content.experienceDashboardNestedCard(cornerRadius: cornerRadius)
        }
    }
}
