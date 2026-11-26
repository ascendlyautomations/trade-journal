import SwiftUI

extension View {
    /// Plain buttons hit-test opaque pixels, so padding and the gap between a title and its chevron are missed.
    /// This fills the control’s layout bounds without changing how it looks.
    func experienceControlHitTarget() -> some View {
        background(Color.white.opacity(0.001))
            .contentShape(Rectangle())
    }
}

/// Replaces `.plain` / `.borderless` so the whole label is tappable, including padding and gaps.
struct ExperiencePlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .experienceControlHitTarget()
    }
}

extension ButtonStyle where Self == ExperiencePlainButtonStyle {
    static var experiencePlain: ExperiencePlainButtonStyle { ExperiencePlainButtonStyle() }
}

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
    /// When true, primary/destructive colors stay at full opacity while `isEnabled` is false.
    var keepsEnabledAppearanceWhenDisabled: Bool = false
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
                        .tint(buttonForeground)
                } else if let icon {
                    ExperienceIcon(icon: icon, size: .sm, color: buttonForeground)
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
            .background(buttonBackground)
            .foregroundStyle(buttonForeground)
            .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous))
            .overlay {
                if kind == .secondary {
                    RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous)
                        .stroke(colors.border, lineWidth: ExperienceBorder.thin)
                }
            }
            .opacity(isEnabled || keepsEnabledAppearanceWhenDisabled
                ? ExperienceOpacity.opaque
                : ExperienceOpacity.disabled)
        }
        .buttonStyle(.experiencePlain)
        .disabled(!isEnabled || isLoading)
        .animation(ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion), value: isLoading)
        .experienceAccessibility(
            label: title,
            identifier: accessibilityIdentifier,
            traits: .isButton
        )
    }

    private var buttonForeground: Color {
        switch kind {
        case .primary: return colors.onAccent
        case .secondary, .text, .icon: return colors.primaryText
        case .destructive: return colors.onAccent
        }
    }

    private var buttonBackground: Color {
        switch kind {
        case .primary:
            return colors.accent
        case .secondary:
            return colors.secondaryBackground
        case .text, .icon:
            return .clear
        case .destructive:
            return colors.error
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
        .buttonStyle(.experiencePlain)
        .experienceAccessibility(
            label: accessibilityLabel,
            identifier: accessibilityIdentifier,
            traits: .isButton
        )
    }
}
