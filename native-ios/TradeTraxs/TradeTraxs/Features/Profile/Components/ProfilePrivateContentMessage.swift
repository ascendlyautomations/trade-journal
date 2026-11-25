import SwiftUI

/// Shown when a private profile's tab content is locked for non-followers.
struct ProfilePrivateContentMessage: View {
    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(spacing: ExperienceSpacing.sm) {
            Image(systemName: "lock.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(colors.secondaryText)
                .accessibilityHidden(true)

            Text("This profile is private")
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .foregroundStyle(colors.primaryText)
                .multilineTextAlignment(.center)

            Text("Request to follow them to see their content.")
                .font(.system(.subheadline, design: .default))
                .foregroundStyle(colors.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, ExperienceSpacing.lg)
        .padding(.vertical, ExperienceSpacing.xxl)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("profile.privateContent")
    }
}