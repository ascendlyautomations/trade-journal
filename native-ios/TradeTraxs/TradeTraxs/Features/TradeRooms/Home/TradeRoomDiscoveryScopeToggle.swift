import SwiftUI

/// All / Official / Community / Your Rooms filter for Trade Rooms discovery.
struct TradeRoomDiscoveryScopeToggle: View {
    let scope: TradeRoomDiscoveryScope
    let onSelect: (TradeRoomDiscoveryScope) -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: ExperienceSpacing.xs) {
            ForEach(TradeRoomDiscoveryScope.allCases) { value in
                let selected = scope == value
                Button {
                    guard scope != value else { return }
                    onSelect(value)
                } label: {
                    Text(value.title)
                        .font(.caption.weight(selected ? .semibold : .regular))
                        .foregroundStyle(selected ? colors.primaryText : colors.secondaryText)
                        .padding(.horizontal, ExperienceSpacing.sm)
                        .padding(.vertical, 5)
                        .background(
                            selected ? colors.fillSecondary : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("tradeRooms.discovery.scope.\(value.rawValue)")
            }
            Spacer(minLength: 0)
        }
        .accessibilityIdentifier("tradeRooms.discovery.scopeToggle")
    }
}
