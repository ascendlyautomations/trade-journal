import SwiftUI

/// Tappable Dashboard section header with disclosure chevron (section collapse).
struct DashboardCollapsibleSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    let isExpanded: Bool
    var trailing: AnyView? = nil
    let onToggle: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
            Button {
                ExperienceHaptics.play(.selection)
                onToggle()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .experienceStyle(.headline, color: colors.primaryText)
                    if let subtitle {
                        Text(subtitle)
                            .experienceStyle(.caption, color: colors.tertiaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse section" : "Expand section")
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.vertical, ExperienceSpacing.xs)
        .accessibilityAddTraits(.isHeader)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(subtitle.map { "\(title). \($0)" } ?? title)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}

struct DashboardInsightViewMoreControl: View {
    let isExpanded: Bool
    let action: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Button(action: action) {
            Text(isExpanded ? "View Less" : "View More")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(colors.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, ExperienceSpacing.xxs)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dashboard.insightViewMore")
    }
}

enum DashboardInsightPresentation {
    static let previewCount = 2
}
