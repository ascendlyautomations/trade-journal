import SwiftUI

/// Tappable Dashboard section header with disclosure chevron (section collapse).
struct DashboardCollapsibleSectionHeader: View {
    let title: String
    var info: String? = nil
    let isExpanded: Bool
    var trailing: AnyView? = nil
    let onToggle: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
            HStack(alignment: .center, spacing: ExperienceSpacing.xxs) {
                Button {
                    ExperienceHaptics.play(.selection)
                    onToggle()
                } label: {
                    Text(title)
                        .experienceStyle(.headline, color: colors.primaryText)
                }
                .buttonStyle(.experiencePlain)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel(title)
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

                if let info {
                    AnalyticsMetricInfoButton(
                        title: title,
                        bodyText: info,
                        accessibilityID: "dashboard.sectionInfo.\(DashboardChartInfo.identifier(for: title))"
                    )
                }
            }

            Spacer(minLength: 0)

            if let trailing {
                trailing
            }

            Button {
                ExperienceHaptics.play(.selection)
                onToggle()
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(colors.tertiaryText)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.experiencePlain)
            .accessibilityLabel(isExpanded ? "Collapse section" : "Expand section")
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.vertical, ExperienceSpacing.xs)
    }
}

struct DashboardInsightViewMoreControl: View {
    let isExpanded: Bool
    var collapsedTitle: String = "View More"
    var expandedTitle: String = "Show fewer insights"
    let action: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Button(action: action) {
            Text(isExpanded ? expandedTitle : collapsedTitle)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(colors.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, ExperienceSpacing.xxs)
        }
        .buttonStyle(.experiencePlain)
        .accessibilityIdentifier("dashboard.insightViewMore")
    }
}

enum DashboardInsightPresentation {
    static let previewCount = 2
}
