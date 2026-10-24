import SwiftUI

/// Outcome filter + sort controls — lives inside ``ProfileSectionContainerChrome`` (Stats parity).
struct ProfileTradesFilterBar: View {
    @Bindable var viewModel: TradesContainerViewModel
    @Binding var browseLayout: ProfileBrowseLayout

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: ExperienceSpacing.xs) {
            HStack(spacing: ExperienceSpacing.xxs) {
                ForEach(ProfileTradesFilter.allCases) { filter in
                    ExperienceChip(
                        title: filter.title,
                        isSelected: viewModel.filter == filter,
                        compact: true,
                        textRole: .footnote
                    ) {
                        viewModel.setFilter(filter)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityIdentifier("profile.trades.filter.\(filter.rawValue)")
                }
            }
            .layoutPriority(1)

            Spacer(minLength: ExperienceSpacing.xxs)

            Menu {
                ForEach(ProfileTradesSort.allCases) { sort in
                    Button {
                        viewModel.setSort(sort)
                    } label: {
                        if viewModel.sort == sort {
                            Label(sort.title, systemImage: "checkmark")
                        } else {
                            Text(sort.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(viewModel.sort.title)
                        .experienceStyle(.footnote, color: colors.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(colors.primaryText)
                }
                .padding(.horizontal, ExperienceSpacing.xs)
                .padding(.vertical, 5)
                .background(colors.fillSecondary)
                .clipShape(Capsule())
                .experienceControlHitTarget()
            }
            .buttonStyle(.experiencePlain)
            .accessibilityLabel("Sort trades")
            .accessibilityValue(viewModel.sort.title)
            .accessibilityIdentifier("profile.trades.sort")

            ProfileBrowseLayoutToggle(layout: $browseLayout, compact: true)
                .fixedSize()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.trades.filters")
    }
}
