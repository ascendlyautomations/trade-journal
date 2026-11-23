import SwiftUI

/// Full-sheet fallback when the viewer cannot join the current broadcast session.
struct BroadcastViewerSessionAccessDeniedView: View {
    let denial: BroadcastViewerSessionAccessDenied
    @Bindable var coordinator: RoomBroadcastCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(spacing: ExperienceSpacing.lg) {
            Spacer(minLength: ExperienceSpacing.xl)

            Image(systemName: "person.fill.xmark")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(colors.warning)
                .accessibilityHidden(true)

            Text("You've Been Removed")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(colors.primaryText)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text("You've been removed from this livestream session.")
                .font(ExperienceTypography.body)
                .foregroundStyle(colors.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, ExperienceSpacing.md)

            ExperienceButton(title: "Close", kind: .primary) {
                coordinator.closeViewerSessionAccessDenied()
                dismiss()
            }
            .padding(.top, ExperienceSpacing.sm)

            Spacer(minLength: ExperienceSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.primaryBackground)
        .accessibilityElement(children: .contain)
    }
}