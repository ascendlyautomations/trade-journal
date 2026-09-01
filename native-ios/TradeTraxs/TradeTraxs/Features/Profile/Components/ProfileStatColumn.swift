import SwiftUI

struct ProfileStatColumn: View {
    let value: String
    let label: String
    var isLoading: Bool = false

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(spacing: ExperienceSpacing.xxs) {
            if isLoading {
                ExperienceSkeleton(height: 18, cornerRadius: ExperienceRadius.xs)
                    .frame(width: 36)
                ExperienceSkeleton(height: 10, cornerRadius: ExperienceRadius.xs)
                    .frame(width: 44)
            } else {
                // Dense header row: values first, labels stay on a single line
                // (incl. "Profit Factor" across five columns).
                Text(value)
                    .font(.system(.footnote, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(colors.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.system(.caption2, design: .default))
                    .foregroundStyle(colors.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isLoading ? "\(label) loading" : "\(value) \(label)")
    }
}
