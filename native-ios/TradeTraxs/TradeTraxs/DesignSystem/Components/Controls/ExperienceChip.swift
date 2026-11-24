import SwiftUI

struct ExperienceTag: View {
    let title: String
    var tone: BannerTone = .info

    @Environment(\.themeColors) private var colors

    var body: some View {
        let toneColor = tone.color(in: colors)
        Text(title)
            .experienceStyle(.caption2, color: toneColor)
            .padding(.horizontal, ExperienceSpacing.xs)
            .padding(.vertical, ExperienceSpacing.xxs)
            .background(toneColor.opacity(ExperienceOpacity.subtle))
            .clipShape(Capsule())
            .experienceAccessibility(label: title, identifier: "tag.\(title)")
    }
}

struct ExperienceChip: View {
    let title: String
    var isSelected: Bool = false
    /// Tighter padding and type for dense rows (e.g. profile trader type).
    var compact: Bool = false
    /// Overrides the compact or regular text size when a row needs a size in between.
    var textRole: TypographyRole? = nil
    var action: (() -> Void)? = nil

    @Environment(\.themeColors) private var colors

    var body: some View {
        Button {
            ExperienceHaptics.play(.selection)
            action?()
        } label: {
            Text(title)
                .experienceStyle(
                    textRole ?? (compact ? .caption : .callout),
                    color: isSelected ? colors.onAccent : colors.primaryText
                )
                .lineLimit(1)
                .minimumScaleFactor(compact ? 0.9 : 1)
                .padding(.horizontal, compact ? ExperienceSpacing.xs : ExperienceSpacing.sm)
                .padding(.vertical, compact ? ExperienceSpacing.xxs : ExperienceSpacing.xs)
                .background {
                    if isSelected {
                        Capsule().fill(colors.accent)
                    } else {
                        Color.clear
                    }
                }
                .modifier(ExperienceChipUnselectedChrome(isSelected: isSelected))
        }
        .buttonStyle(.experiencePlain)
        .disabled(action == nil)
        .experienceAccessibility(
            label: title,
            identifier: "chip.\(title)",
            traits: isSelected ? [.isButton, .isSelected] : .isButton
        )
    }
}

private struct ExperienceChipUnselectedChrome: ViewModifier {
    var isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.themeColors) private var colors

    func body(content: Content) -> some View {
        if isSelected {
            content
        } else if colorScheme == .light {
            content.experienceFilterCapsule()
        } else {
            content.background(colors.fillSecondary, in: Capsule())
        }
    }
}

struct ExperienceBadge: View {
    let value: Int
    var maxDisplay: Int = 99

    @Environment(\.themeColors) private var colors

    var body: some View {
        Text(display)
            .experienceStyle(.caption2, color: colors.onAccent)
            .padding(.horizontal, ExperienceSpacing.xxs + 2)
            .frame(minWidth: 18, minHeight: 18)
            .background(colors.error)
            .clipShape(Capsule())
            .accessibilityLabel(Text("\(value) new"))
            .accessibilityIdentifier("badge.count")
    }

    private var display: String {
        value > maxDisplay ? "\(maxDisplay)+" : "\(value)"
    }
}
