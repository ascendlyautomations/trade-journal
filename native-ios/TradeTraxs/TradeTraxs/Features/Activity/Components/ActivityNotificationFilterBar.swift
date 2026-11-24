import SwiftUI

/// Compact Date + Type filters below the Activity navigation title.
struct ActivityNotificationFilterBar: View {
    @Bindable var viewModel: ActivityHomeViewModel

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: ExperienceSpacing.xs) {
            filterMenu(
                title: viewModel.dateFilterLabel,
                accessibilityIdentifier: "activity.filter.date"
            ) {
                ForEach(ActivityNotificationDateFilter.allCases) { option in
                    Button {
                        viewModel.selectDateFilter(option)
                    } label: {
                        if viewModel.dateFilter == option {
                            Label(option.menuTitle, systemImage: "checkmark")
                        } else {
                            Text(option.menuTitle)
                        }
                    }
                    .accessibilityIdentifier("activity.filter.date.\(option.rawValue)")
                }
            }
            .layoutPriority(1)

            filterMenu(
                title: viewModel.typeFilterLabel,
                accessibilityIdentifier: "activity.filter.type"
            ) {
                ForEach(ActivityNotificationTypeCategory.allCases) { option in
                    Button {
                        viewModel.selectTypeFilter(option)
                    } label: {
                        if viewModel.typeFilter == option {
                            Label(option.menuTitle, systemImage: "checkmark")
                        } else {
                            Text(option.menuTitle)
                        }
                    }
                    .accessibilityIdentifier("activity.filter.type.\(option.rawValue)")
                }
            }
            .layoutPriority(1)
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.top, ExperienceSpacing.xs)
        .padding(.bottom, ActivityInboxLayout.filterBarBottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.backgroundPrimary)
        .accessibilityIdentifier("activity.filterBar")
    }

    private func filterMenu<Content: View>(
        title: String,
        accessibilityIdentifier: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu(content: content) {
            HStack(spacing: 4) {
                Text(title)
                    .experienceStyle(.footnote, color: colors.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                ExperienceIcon(icon: .chevronDown, size: .xs, color: colors.secondaryText)
            }
            .padding(.horizontal, ExperienceSpacing.sm)
            .frame(minHeight: 32)
            .frame(maxWidth: .infinity)
            .experienceFilterCapsule()
        }
        .buttonStyle(.experiencePlain)
        .accessibilityLabel(accessibilityIdentifier)
        .accessibilityValue(title)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}