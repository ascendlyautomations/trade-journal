import SwiftUI

/// Compact SF Symbol filter strip — All / Trades / Posts / Clips / Achievements.
struct FeedContentToggle: View {
    @Binding var filter: FeedContentFilter
    let onChange: (FeedContentFilter) -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            ForEach(FeedContentFilter.allCases, id: \.self) { value in
                filterButton(value)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feed.contentFilter")
    }

    private func filterButton(_ value: FeedContentFilter) -> some View {
        let selected = filter == value
        return Button {
            guard filter != value else { return }
            ExperienceHaptics.play(.selection)
            filter = value
            onChange(value)
        } label: {
            VStack(spacing: 3) {
                ExperienceIcon(
                    icon: value.icon,
                    size: .md,
                    color: selected ? colors.primaryText : colors.secondaryText
                )
                Text(value.title)
                    .experienceStyle(
                        .caption2,
                        color: selected ? colors.primaryText : colors.secondaryText
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(minWidth: 48)
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(
                selected
                    ? colors.fillSecondary
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("feed.filter.\(value.rawValue)")
    }
}
