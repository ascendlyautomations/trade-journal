import SwiftUI

/// Holds the latest psychology analytics report for dashboard → detail navigation.
@MainActor
final class PsychologyAnalyticsSessionStore {
    static let shared = PsychologyAnalyticsSessionStore()

    private(set) var report: PsychologyAnalyticsReport?
    var highlightedSectionID: String?

    private init() {}

    func update(_ report: PsychologyAnalyticsReport?) {
        self.report = report
    }

    func focusSection(_ sectionID: String?) {
        highlightedSectionID = sectionID
    }
}

struct PsychologyAnalyticsDetailView: View {
    let report: PsychologyAnalyticsReport
    var highlightedSectionID: String?
    var onOpenCoach: (() -> Void)?
    var onOpenCheckInHistory: (() -> Void)?

    @Environment(\.themeColors) private var colors

    private var coachSummary: PsychologyCoachSummary? {
        PsychologyCoachSessionStore.shared.deterministicSummary
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
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
                        patternsSection
                    }

                    ForEach(report.sections) { section in
                        sectionView(section)
                            .id(section.id)
                    }
                }
                .padding(.vertical, ExperienceSpacing.md)
            }
            .onAppear {
                guard let highlightedSectionID else { return }
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

    private var patternsSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Your Patterns")
                .experienceStyle(.headline, color: colors.primaryText)
                .padding(.horizontal, ExperienceSpacing.md)

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
            .padding(.horizontal, ExperienceSpacing.md)
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

            if row.metrics.reliability == .insufficient {
                Text("Not enough data yet (\(row.metrics.tradeCount) trades)")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            } else {
                HStack(spacing: ExperienceSpacing.md) {
                    metricPill("Trades", value: "\(row.metrics.tradeCount)")
                    metricPill("Win", value: TraderPsychologyAnalyticsEngine.formatWinRate(row.metrics.winRate))
                    metricPill("Avg", value: TraderPsychologyAnalyticsEngine.money(row.metrics.averagePnL ?? 0))
                    metricPill("Exp", value: TraderPsychologyAnalyticsEngine.money(row.metrics.expectancy ?? 0))
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
