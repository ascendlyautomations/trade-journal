import SwiftUI

/// Dedicated public statistics row beneath the Profile identity block.
///
/// Pass any ordered ``ProfileHeaderMetric`` list — the layout expands without
/// redesigning the header.
struct ProfileStatisticsRow: View {
    let metrics: [ProfileHeaderMetric]
    var isLoading: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(metrics) { metric in
                ProfileStatColumn(
                    value: metric.value,
                    label: metric.label,
                    isLoading: isLoading
                )
            }
        }
        .padding(.vertical, ExperienceSpacing.xs)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.statisticsRow")
    }
}
