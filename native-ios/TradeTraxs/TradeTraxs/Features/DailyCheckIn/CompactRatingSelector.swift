import SwiftUI

enum CompactRatingSelectorDensity {
    case standard
    case compact
}

/// Compact 1–5 selector with optional endpoint labels.
struct CompactRatingSelector: View {
    let title: String
    @Binding var value: Int
    var lowLabel: String?
    var highLabel: String?
    var density: CompactRatingSelectorDensity = .standard

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isCompact: Bool { density == .compact }

    private var titleFont: Font {
        isCompact
            ? ExperienceTypography.footnote.weight(.semibold)
            : ExperienceTypography.subheadline.weight(.semibold)
    }

    private var valueFont: Font {
        isCompact
            ? ExperienceTypography.callout.weight(.semibold)
            : ExperienceTypography.subheadline.weight(.semibold)
    }

    private var rowVerticalPadding: CGFloat {
        isCompact ? ExperienceSpacing.xs : ExperienceSpacing.sm
    }

    private var stackSpacing: CGFloat {
        isCompact ? ExperienceSpacing.xxs : ExperienceSpacing.xs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: stackSpacing) {
            Text(title)
                .font(titleFont)
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
                            .font(valueFont)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, rowVerticalPadding)
                            .frame(minHeight: ExperienceSpacing.minTouchTarget)
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
                    .buttonStyle(.experiencePlain)
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
