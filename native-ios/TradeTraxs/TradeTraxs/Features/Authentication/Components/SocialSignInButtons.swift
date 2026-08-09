import SwiftUI

struct SocialSignInButtons: View {
    var isEnabled: Bool
    var isLoading: Bool
    var onApple: () -> Void
    var onGoogle: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(spacing: ExperienceSpacing.sm) {
            socialButton(
                title: "Continue with Apple",
                systemImage: "apple.logo",
                identifier: "auth.apple",
                action: onApple
            )
            socialButton(
                title: "Continue with Google",
                systemImage: "g.circle.fill",
                identifier: "auth.google",
                action: onGoogle
            )
        }
    }

    private func socialButton(
        title: String,
        systemImage: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard isEnabled, !isLoading else { return }
            ExperienceHaptics.play(.selection)
            action()
        } label: {
            HStack(spacing: ExperienceSpacing.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(ExperienceTypography.headline)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: ExperienceAccessibility.minTouchTarget)
            .foregroundStyle(colors.primaryText)
            .background(colors.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous)
                    .stroke(colors.border, lineWidth: ExperienceBorder.thin)
            }
            .opacity(isEnabled && !isLoading ? ExperienceOpacity.opaque : ExperienceOpacity.disabled)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(title)
    }
}

struct AuthDivider: View {
    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: ExperienceSpacing.md) {
            Rectangle()
                .fill(colors.separator)
                .frame(height: ExperienceBorder.thin)
            Text("or")
                .experienceStyle(.footnote, color: colors.secondaryText)
            Rectangle()
                .fill(colors.separator)
                .frame(height: ExperienceBorder.thin)
        }
        .accessibilityHidden(true)
    }
}
