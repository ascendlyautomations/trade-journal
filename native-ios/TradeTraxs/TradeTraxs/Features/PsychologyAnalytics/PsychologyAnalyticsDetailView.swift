import SwiftUI

/// Holds the latest psychology analytics report for dashboard → detail navigation.
@MainActor
final class PsychologyAnalyticsSessionStore {
    static let shared = PsychologyAnalyticsSessionStore()

    private(set) var report: PsychologyAnalyticsReport?
    private(set) var unlockProgress: PsychologyInsightsUnlockProgress = .zero
    private(set) var postUnlockGapMessages: [String] = []
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
        profileID: ProfileID?,
        scopeFingerprint: String?,
        scopeLabel: String? = nil
    ) {
        self.report = report
        self.unlockProgress = unlockProgress
        self.postUnlockGapMessages = postUnlockGapMessages
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
    var unlockProgress: PsychologyInsightsUnlockProgress = .zero
    var postUnlockGapMessages: [String] = []
    var highlightedSectionID: String?
    var onOpenCoach: (() -> Void)?
    var onOpenCheckInHistory: (() -> Void)?

    @Environment(\.themeColors) private var colors
    @State private var advancedExpanded = false

    private static let advancedSectionIDs: Set<String> = [
        "sleep", "mentalState", "conviction", "discipline", "emotion",
        "afterLosses", "tradeFrequency", "combined"
    ]

    private var coachSummary: PsychologyCoachSummary? {
        PsychologyCoachSessionStore.shared.deterministicSummary
    }

    private var advancedSections: [PsychologyAnalyticsSection] {
        report.sections.filter { Self.advancedSectionIDs.contains($0.id) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                    overviewSection

                    if let coachSummary {
                        PsychologySummarySection(summary: coachSummary, onOpenCoach: onOpenCoach)
                    }

                    if let onOpenCheckInHistory {
                        Button(action: onOpenCheckInHistory) {
                            Label("Check-In History", systemImage: "calendar")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .padding(.horizontal, ExperienceSpacing.md)
                    }

                    if !report.dashboardCards.isEmpty {
                        comparisonInsightsSection
                    } else if !unlockProgress.showsRequirementMessage {
                        insightGapSection
                    }

                    advancedAnalyticsSection
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
        .accessibilityIdentifier("psychologyAnalytics.detail")
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Overview")
                .experienceStyle(.headline, color: colors.primaryText)
                .padding(.horizontal, ExperienceSpacing.md)

            HStack(spacing: ExperienceSpacing.xs) {
                countTile(
                    value: unlockProgress.tradingDayCheckInCount,
                    label: "Check-in days"
                )
                countTile(value: report.baseline.tradeCount, label: "Qualifying trades")
                countTile(value: report.checkInMatchedTradeCount, label: "Matched days")
            }
            .padding(.horizontal, ExperienceSpacing.md)

            if !unlockProgress.showsRequirementMessage {
                VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                    Text("Your trades in this scope")
                        .experienceStyle(.caption, color: colors.tertiaryText)
                        .fontWeight(.semibold)
                    HStack(spacing: ExperienceSpacing.md) {
                        metricPill(
                            "Win rate",
                            value: TraderPsychologyAnalyticsEngine.formatWinRate(report.baseline.winRate)
                        )
                        metricPill(
                            "Avg P&L / trade",
                            value: TraderPsychologyAnalyticsEngine.money(report.baseline.averagePnL ?? 0)
                        )
                        metricPill(
                            "Expected $ / trade",
                            value: TraderPsychologyAnalyticsEngine.money(report.baseline.expectancy ?? 0)
                        )
                    }
                }
                .padding(ExperienceSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(colors.surfacePrimary, in: RoundedRectangle(cornerRadius: ExperienceRadius.sm))
                .overlay {
                    RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                        .stroke(colors.border, lineWidth: 1)
                }
                .padding(.horizontal, ExperienceSpacing.md)
            }
        }
        .accessibilityIdentifier("psychologyAnalytics.overview")
    }

    private var comparisonInsightsSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Comparison insights")
                .experienceStyle(.headline, color: colors.primaryText)
            Text("Statistically meaningful patterns — not proof of causation.")
                .experienceStyle(.caption, color: colors.tertiaryText)

            VStack(spacing: ExperienceSpacing.xs) {
                ForEach(report.dashboardCards) { card in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.headline)
                            .experienceStyle(.subheadline, color: colors.primaryText)
                            .fontWeight(.semibold)
                        Text(card.detail)
                            .experienceStyle(.footnote, color: colors.secondaryText)
                        Text("\(card.sampleSize) trades · \(card.reliability.label)")
                            .experienceStyle(.caption2, color: colors.tertiaryText)
                    }
                    .padding(ExperienceSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(colors.surfacePrimary, in: RoundedRectangle(cornerRadius: ExperienceRadius.sm))
                    .overlay {
                        RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                            .stroke(colors.border, lineWidth: 1)
                    }
                }
            }
        }
        .padding(.horizontal, ExperienceSpacing.md)
    }

    private var insightGapSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("What to log next")
                .experienceStyle(.subheadline, color: colors.primaryText)
                .fontWeight(.semibold)
            Text(
                "Your analytics overview is unlocked. Comparison cards appear when groups have enough matched, tagged trades."
            )
            .experienceStyle(.caption, color: colors.secondaryText)
            ForEach(postUnlockGapMessages, id: \.self) { message in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                    Text(message)
                        .experienceStyle(.caption, color: colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfacePrimary, in: RoundedRectangle(cornerRadius: ExperienceRadius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                .stroke(colors.border, lineWidth: 1)
        }
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
                        Text("Sleep, mental state, conviction, discipline, emotion, and more")
                            .experienceStyle(.caption, color: colors.tertiaryText)
                    }
                    Spacer(minLength: 0)
                    Text(advancedExpanded ? "Hide" : "Show")
                        .experienceStyle(.footnote, color: colors.accent)
                        .fontWeight(.semibold)
                }
                .padding(ExperienceSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(colors.surfacePrimary, in: RoundedRectangle(cornerRadius: ExperienceRadius.sm))
                .overlay {
                    RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                        .stroke(colors.border, lineWidth: 1)
                }
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
        .background(colors.surfacePrimary, in: RoundedRectangle(cornerRadius: ExperienceRadius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                .stroke(colors.border, lineWidth: 1)
        }
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

            if row.metrics.tradeCount == 0 {
                Text("No trades in this group yet")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            } else if row.metrics.reliability == .insufficient {
                Text("Preview · \(row.metrics.tradeCount) trade\(row.metrics.tradeCount == 1 ? "" : "s")")
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .fontWeight(.medium)
                HStack(spacing: ExperienceSpacing.md) {
                    metricPill("Win rate", value: TraderPsychologyAnalyticsEngine.formatWinRate(row.metrics.winRate))
                    metricPill("Avg P&L / trade", value: TraderPsychologyAnalyticsEngine.money(row.metrics.averagePnL ?? 0))
                }
                Text("\(row.metrics.reliability.label) — need 5+ trades for a reliable read")
                    .experienceStyle(.caption2, color: colors.tertiaryText)
            } else {
                HStack(spacing: ExperienceSpacing.md) {
                    metricPill("Trades", value: "\(row.metrics.tradeCount)")
                    metricPill("Win rate", value: TraderPsychologyAnalyticsEngine.formatWinRate(row.metrics.winRate))
                    metricPill("Avg P&L / trade", value: TraderPsychologyAnalyticsEngine.money(row.metrics.averagePnL ?? 0))
                    metricPill("Expected $ / trade", value: TraderPsychologyAnalyticsEngine.money(row.metrics.expectancy ?? 0))
                }
                Text(row.metrics.reliability.label)
                    .experienceStyle(.caption2, color: colors.tertiaryText)
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
