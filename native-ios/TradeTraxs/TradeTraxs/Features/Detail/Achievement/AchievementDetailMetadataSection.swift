import SwiftUI

/// Achievement caption and description; headline + meta chips live in the parent scroll.
struct AchievementDetailMetadataSection: View {
    let achievement: Achievement

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            if let description = normalizedDescription {
                Text(description)
                    .experienceStyle(.body, color: colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("detail.achievement.description")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.achievement.metadata")
    }

    private var normalizedDescription: String? {
        let trimmed = achievement.description?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}