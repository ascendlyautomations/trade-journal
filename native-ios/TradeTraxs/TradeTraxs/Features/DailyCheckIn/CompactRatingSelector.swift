import SwiftUI

/// Compact 1–5 selector with optional endpoint labels.
struct CompactRatingSelector: View {
    let title: String
    @Binding var value: Int
    var lowLabel: String?
    var highLabel: String?

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text(title)
                .font(ExperienceTypography.subheadline.weight(.semibold))
                .foregroundStyle(colors.primaryText)

            HStack(spacing: ExperienceSpacing.xs) {
                ForEach(1...5, id: \.self) { level in
                    Button {
                        ExperienceHaptics.play(.selection)
                        ExperienceMotion.withAnimation(ExperienceMotion.selection, reduceMotion: reduceMotion) {
                            value = level
                        }
                    } label: {
                        Text("\(level)")
                            .font(ExperienceTypography.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, ExperienceSpacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                                    .fill(
                                        value == level
                                            ? colors.accent.opacity(0.18)
                                            : colors.fillSecondary
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                                    .strokeBorder(
                                        value == level ? colors.accent : colors.separator,
                                        lineWidth: value == level ? 1.5 : 1
                                    )
                            )
                            .foregroundStyle(value == level ? colors.accent : colors.primaryText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title) \(level) of 5")
                    .accessibilityAddTraits(value == level ? .isSelected : [])
                }
            }

            if lowLabel != nil || highLabel != nil {
                HStack {
                    if let lowLabel {
                        Text(lowLabel)
                            .experienceStyle(.caption2, color: colors.tertiaryText)
                    }
                    Spacer()
                    if let highLabel {
                        Text(highLabel)
                            .experienceStyle(.caption2, color: colors.tertiaryText)
                    }
                }
            }
        }
    }
}
