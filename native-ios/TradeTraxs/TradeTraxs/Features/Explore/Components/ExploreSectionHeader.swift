import SwiftUI

struct ExploreSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var trailingTitle: String? = nil
    var onTrailing: (() -> Void)? = nil

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .experienceStyle(.headline, color: colors.primaryText)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .experienceStyle(.caption, color: colors.secondaryText)
                }
            }
            Spacer(minLength: ExperienceSpacing.sm)
            if let trailingTitle, let onTrailing {
                Button(trailingTitle, action: onTrailing)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(colors.accent)
                    .accessibilityIdentifier("explore.section.viewMore")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}
