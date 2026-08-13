import SwiftUI

struct ActivityFollowRequestsBanner: View {
    let count: Int
    var action: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Button(action: action) {
            HStack(spacing: ExperienceSpacing.sm) {
                ExperienceIcon(icon: .profile, size: .md, color: colors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Follow Requests")
                        .experienceStyle(.body, color: colors.primaryText)
                        .fontWeight(.semibold)
                    Text(count == 1 ? "1 request" : "\(count) requests")
                        .experienceStyle(.caption, color: colors.secondaryText)
                }
                Spacer()
                ExperienceIcon(icon: .forward, size: .sm, color: colors.tertiaryText)
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.vertical, ExperienceSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Follow Requests, \(count)")
        .accessibilityIdentifier("activity.followRequests")
    }
}
