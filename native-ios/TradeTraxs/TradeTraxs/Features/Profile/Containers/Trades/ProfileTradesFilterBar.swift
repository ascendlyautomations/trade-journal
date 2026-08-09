import SwiftUI

struct ProfileTradesFilterBar: View {
    @Bindable var viewModel: TradesContainerViewModel

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ExperienceSpacing.xs) {
                    ForEach(ProfileTradesFilter.allCases) { filter in
                        ExperienceChip(
                            title: filter.title,
                            isSelected: viewModel.filter == filter
                        ) {
                            viewModel.setFilter(filter)
                        }
                        .accessibilityIdentifier("profile.trades.filter.\(filter.rawValue)")
                    }
                }
            }

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
                Label(viewModel.sort.title, systemImage: "arrow.up.arrow.down")
                    .font(ExperienceTypography.footnote)
                    .foregroundStyle(colors.primaryText)
                    .padding(.horizontal, ExperienceSpacing.sm)
                    .frame(minHeight: ExperienceAccessibility.minTouchTarget)
                    .background(colors.fillSecondary)
                    .clipShape(Capsule())
            }
            .accessibilityLabel("Sort trades")
            .accessibilityValue(viewModel.sort.title)
            .accessibilityIdentifier("profile.trades.sort")
        }
    }
}
