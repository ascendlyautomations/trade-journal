import SwiftUI

struct ExploreSectionHeader: View {
    let title: String
    var subtitle: String? = nil

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .experienceStyle(.headline, color: colors.primaryText)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .experienceStyle(.caption, color: colors.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}
