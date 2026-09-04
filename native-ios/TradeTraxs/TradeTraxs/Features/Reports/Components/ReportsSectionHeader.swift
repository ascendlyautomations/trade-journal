import SwiftUI

/// Collapsible section header for the Reports catalog.
struct ReportsSectionHeader: View {
    let title: String
    let subtitle: String
    let isExpanded: Bool
    let onToggle: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .experienceStyle(.headline, color: colors.primaryText)
                    Text(subtitle)
                        .experienceStyle(.footnote, color: colors.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: ExperienceSpacing.sm)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(colors.tertiaryText)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.vertical, ExperienceSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint("Double tap to \(isExpanded ? "collapse" : "expand")")
    }
}
