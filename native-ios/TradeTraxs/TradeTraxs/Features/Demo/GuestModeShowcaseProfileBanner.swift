import SwiftUI

/// Profile tab callout while exploring the live showcase account as a guest.
struct GuestModeShowcaseProfileBanner: View {
    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text("Showcase account")
                .experienceStyle(.subheadline, color: colors.primaryText)
                .fontWeight(.semibold)
                .accessibilityAddTraits(.isHeader)
            Text(
                "You're browsing TradeTraxs as a guest. This journal belongs to our public showcase trader—not your personal account."
            )
            .experienceStyle(.footnote, color: colors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.fillSecondary.opacity(0.55), in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                .strokeBorder(colors.border.opacity(0.7), lineWidth: ExperienceBorder.hairline)
        }
        .accessibilityIdentifier("profile.guestShowcase.banner")
    }
}