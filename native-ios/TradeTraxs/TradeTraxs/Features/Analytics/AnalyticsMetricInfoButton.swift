import SwiftUI

/// Compact ⓘ control for metric explanations (Dashboard Scorecard popover styling).
struct AnalyticsMetricInfoButton: View {
    let title: String
    let bodyText: String
    var accessibilityID: String?

    @State private var showsInfo = false
    @State private var popoverArrowEdge: Edge = .top
    @State private var anchorInScreen: CGRect = .zero
    @Environment(\.themeColors) private var colors
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Button {
            presentInfoPopover()
        } label: {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(colors.tertiaryText)
                .frame(width: 28, height: 28, alignment: .center)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .experienceInfoPopoverAnchorTracking($anchorInScreen)
        .accessibilityLabel("About \(title)")
        .accessibilityIdentifier(accessibilityID ?? "experience.infoPopover")
        .popover(isPresented: $showsInfo, attachmentAnchor: .rect(.bounds), arrowEdge: popoverArrowEdge) {
            ExperienceInfoPopoverContent(title: title, bodyText: bodyText)
        }
    }

    private func presentInfoPopover() {
        let width = ExperienceInfoPopoverMetrics.resolvedWidth(horizontalSizeClass: horizontalSizeClass)
        let height = ExperienceInfoPopoverMetrics.estimatedContentHeight(
            title: title,
            bodyText: bodyText,
            contentWidth: width
        )
        popoverArrowEdge = ExperienceInfoPopoverPlacement.preferredArrowEdge(
            anchorInScreen: anchorInScreen,
            estimatedPopoverHeight: height
        )
        showsInfo = true
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