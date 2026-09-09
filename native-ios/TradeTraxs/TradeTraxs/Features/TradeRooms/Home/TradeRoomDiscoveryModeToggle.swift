import SwiftUI

/// Suggested / Popular switch for Trade Rooms discovery.
struct TradeRoomDiscoveryModeToggle: View {
    let mode: TradeRoomDiscoveryMode
    let onSelect: (TradeRoomDiscoveryMode) -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: ExperienceSpacing.xs) {
            ForEach(TradeRoomDiscoveryMode.allCases) { value in
                let selected = mode == value
                Button {
                    guard mode != value else { return }
                    onSelect(value)
                } label: {
                    Text(value.title)
                        .font(.subheadline.weight(selected ? .semibold : .regular))
                        .foregroundStyle(selected ? colors.primaryText : colors.secondaryText)
                        .padding(.horizontal, ExperienceSpacing.sm)
                        .padding(.vertical, 6)
                        .background(
                            selected ? colors.fillSecondary : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("tradeRooms.discovery.mode.\(value.rawValue)")
            }
            Spacer(minLength: 0)
        }
        .accessibilityIdentifier("tradeRooms.discovery.modeToggle")
    }
}
