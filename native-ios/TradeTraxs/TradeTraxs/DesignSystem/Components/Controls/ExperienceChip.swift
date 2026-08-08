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
    var action: (() -> Void)? = nil

    @Environment(\.themeColors) private var colors

    var body: some View {
        Button {
            ExperienceHaptics.play(.selection)
            action?()
        } label: {
            Text(title)
                .experienceStyle(
                    .callout,
                    color: isSelected ? colors.onAccent : colors.primaryText
                )
                .padding(.horizontal, ExperienceSpacing.sm)
                .padding(.vertical, ExperienceSpacing.xs)
                .background(isSelected ? colors.accent : colors.fillSecondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .experienceAccessibility(
            label: title,
            identifier: "chip.\(title)",
            traits: isSelected ? [.isButton, .isSelected] : .isButton
        )
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
