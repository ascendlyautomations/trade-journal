import SwiftUI

/// Compact ⓘ control for analytics metric explanations (native popover).
struct AnalyticsMetricInfoButton: View {
    let title: String
    let bodyText: String
    var accessibilityID: String?

    @State private var showsInfo = false
    @Environment(\.themeColors) private var colors

    var body: some View {
        Button {
            showsInfo = true
        } label: {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(colors.tertiaryText)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About \(title)")
        .accessibilityIdentifier(accessibilityID ?? "analytics.metricInfo")
        .popover(isPresented: $showsInfo) {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                Text(title)
                    .font(ExperienceTypography.subheadline.weight(.semibold))
                    .foregroundStyle(colors.primaryText)
                Text(bodyText)
                    .font(ExperienceTypography.footnote)
                    .foregroundStyle(colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(ExperienceSpacing.md)
            .frame(width: 280, alignment: .leading)
            .experienceAnalyticsPopoverChrome()
        }
    }
}

struct AnalyticsSectionHeader: View {
    let title: String
    var infoTitle: String?
    var infoBody: String?
    var infoAccessibilityID: String?

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.xxs) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colors.primaryText)
            if let infoTitle, let infoBody {
                AnalyticsMetricInfoButton(
                    title: infoTitle,
                    bodyText: infoBody,
                    accessibilityID: infoAccessibilityID
                )
            }
            Spacer(minLength: 0)
        }
    }
}
