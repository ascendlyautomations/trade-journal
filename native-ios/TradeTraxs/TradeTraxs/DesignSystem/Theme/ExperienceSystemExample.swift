import SwiftUI

/// Documentation-oriented example of how a future screen consumes the Experience System.
///
/// Not a product feature. Safe to delete once feature modules demonstrate usage.
struct ExperienceSystemConsumptionExample: View {
    @Environment(\.experienceTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var showToast = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                Text("Today")
                    .experienceStyle(.largeTitle)

                Text("+1,240.50")
                    .experienceStyle(.metricLarge, color: theme.metricColor(for: 1240.50))

                ExperienceSearchField(text: $query)

                ExperienceCard {
                    VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                        ExperienceListRow(title: "Sample row", subtitle: "Uses shared list row")
                        ExperienceDivider()
                        HStack {
                            ExperienceTag(title: "Live", tone: .success)
                            ExperienceChip(title: "Filter", isSelected: true)
                            Spacer()
                            ExperienceBadge(value: 3)
                        }
                    }
                }

                ExperienceButton(title: "Save Trade", icon: .checkmark, kind: .primary) {
                    ExperienceHaptics.play(.tradeSaved)
                    ExperienceMotion.withAnimation(
                        ExperienceMotion.success,
                        reduceMotion: reduceMotion
                    ) {
                        showToast = true
                    }
                }

                if showToast {
                    ExperienceToast(message: "Trade saved", tone: .success)
                }

                ExperienceEmptyState(
                    icon: .trades,
                    title: "No trades yet",
                    message: "When you log your first trade, it will appear here.",
                    actionTitle: "Add Trade",
                    action: {}
                )
            }
            .experiencePadding(.md)
        }
        .experienceScreenBackground()
        .experienceAccessibility(label: "Experience system example")
    }
}

#Preview("Experience System") {
    ExperienceSystemConsumptionExample()
        .experienceTheme()
}
