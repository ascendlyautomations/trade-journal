import SwiftUI

/// Compact category filter for Trade Rooms discovery (All / Popular tabs).
struct TradeRoomCategoryFilterBar: View {
    let selectedCategory: TradeRoomCategory?
    let onSelect: (TradeRoomCategory?) -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.colorScheme) private var colorScheme

    private var selectionTitle: String {
        let value = selectedCategory?.displayName ?? "All"
        return "Category: \(value)"
    }

    var body: some View {
        Menu {
            categoryRow(title: "All", isSelected: selectedCategory == nil) {
                onSelect(nil)
            }
            ForEach(TradeRoomCategory.allCases, id: \.self) { category in
                categoryRow(
                    title: category.displayName,
                    isSelected: selectedCategory == category
                ) {
                    onSelect(category)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(selectionTitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(colors.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(colorScheme == .light ? colors.secondaryText : colors.tertiaryText)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(colors.fillSecondary)
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(colors.border.opacity(0.45), lineWidth: ExperienceBorder.hairline)
            }
            .contentShape(Capsule(style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.experiencePlain)
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Category")
        .accessibilityValue(selectedCategory?.displayName ?? "All")
        .accessibilityIdentifier("tradeRooms.discovery.categoryFilter")
    }

    private func categoryRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.footnote)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.semibold))
                }
            }
        }
    }
}