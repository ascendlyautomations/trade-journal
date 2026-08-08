import SwiftUI

enum ExperienceButtonStyleKind: Sendable {
    case primary
    case secondary
    case destructive
    case text
    case icon
}

struct ExperienceButton: View {
    let title: String
    var icon: AppIcon? = nil
    var kind: ExperienceButtonStyleKind = .primary
    var isEnabled: Bool = true
    var isLoading: Bool = false
    var accessibilityIdentifier: String? = nil
    let action: () -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: {
            guard isEnabled, !isLoading else { return }
            ExperienceHaptics.play(kind == .destructive ? .warning : .selection)
            action()
        }) {
            HStack(spacing: ExperienceSpacing.xs) {
                if isLoading {
                    ProgressView()
                        .tint(foreground)
                } else if let icon {
                    ExperienceIcon(icon: icon, size: .sm, color: foreground)
                }
                if kind != .icon {
                    Text(title)
                        .font(ExperienceTypography.headline)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: kind == .icon ? nil : .infinity)
            .padding(.horizontal, kind == .text || kind == .icon ? ExperienceSpacing.xs : ExperienceSpacing.md)
            .padding(.vertical, kind == .text ? ExperienceSpacing.xs : ExperienceSpacing.sm)
            .frame(minHeight: ExperienceAccessibility.minTouchTarget)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous))
            .overlay {
                if kind == .secondary {
                    RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous)
                        .stroke(colors.border, lineWidth: ExperienceBorder.thin)
                }
            }
            .opacity(isEnabled ? ExperienceOpacity.opaque : ExperienceOpacity.disabled)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .animation(ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion), value: isLoading)
        .experienceAccessibility(
            label: title,
            identifier: accessibilityIdentifier,
            traits: .isButton
        )
    }

    private var foreground: Color {
        switch kind {
        case .primary: return colors.onAccent
        case .secondary, .text, .icon: return colors.primaryText
        case .destructive: return colors.onAccent
        }
    }

    @ViewBuilder
    private var background: some View {
        switch kind {
        case .primary:
            colors.accent
        case .secondary, .text, .icon:
            Color.clear
        case .destructive:
            colors.error
        }
    }
}

struct ExperienceIconButton: View {
    let icon: AppIcon
    var accessibilityLabel: String
    var accessibilityIdentifier: String? = nil
    let action: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Button(action: {
            ExperienceHaptics.play(.selection)
            action()
        }) {
            ExperienceIcon(icon: icon, size: .md, color: colors.primaryText)
                .experienceTouchTarget()
        }
        .buttonStyle(.plain)
        .experienceAccessibility(
            label: accessibilityLabel,
            identifier: accessibilityIdentifier,
            traits: .isButton
        )
    }
}
