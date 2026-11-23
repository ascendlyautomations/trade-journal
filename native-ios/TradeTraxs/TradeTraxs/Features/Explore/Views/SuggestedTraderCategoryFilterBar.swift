import SwiftUI

/// Horizontally scrollable trader-type filter — matches Trade Rooms category chip styling.
struct SuggestedTraderCategoryFilterBar: View {
    let selected: SuggestedTraderCategoryTab
    let onSelect: (SuggestedTraderCategoryTab) -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ExperienceSpacing.xs) {
                ForEach(SuggestedTraderCategoryTab.allCases) { tab in
                    categoryChip(tab)
                }
            }
            .padding(.vertical, ExperienceSpacing.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("suggestedTraders.categoryFilter")
    }

    private func categoryChip(_ tab: SuggestedTraderCategoryTab) -> some View {
        let isSelected = selected == tab
        return Button {
            guard selected != tab else { return }
            onSelect(tab)
        } label: {
            Text(tab.title)
                .experienceStyle(.footnote, color: isSelected ? colors.accent : colors.primaryText)
                .fontWeight(isSelected ? .semibold : .regular)
                .lineLimit(1)
                .padding(.horizontal, ExperienceSpacing.sm)
                .frame(minHeight: 32)
                .tradingRulesFilterChip()
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: ExperienceRadius.chip, style: .continuous)
                            .stroke(colors.accent.opacity(0.5), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.experiencePlain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("suggestedTraders.category.\(tab.rawValue)")
    }
}