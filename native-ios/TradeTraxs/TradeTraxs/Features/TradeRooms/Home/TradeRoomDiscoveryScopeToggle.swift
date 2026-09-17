import SwiftUI

/// All / Your Rooms / Official / Popular filter for Trade Rooms discovery.
struct TradeRoomDiscoveryScopeToggle: View {
    let scope: TradeRoomDiscoveryScope
    let onSelect: (TradeRoomDiscoveryScope) -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: 6) {
            ForEach(TradeRoomDiscoveryScope.homeToggleOrder) { value in
                scopeChip(value)
            }
        }
        .accessibilityIdentifier("tradeRooms.discovery.scopeToggle")
    }

    private func scopeChip(_ value: TradeRoomDiscoveryScope) -> some View {
        let selected = scope == value
        return Button {
            guard scope != value else { return }
            onSelect(value)
        } label: {
            Text(value.title)
                .font(.caption.weight(selected ? .semibold : .medium))
                .foregroundStyle(selected ? colors.onAccent : colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(1)
                .allowsTightening(true)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background {
                    Capsule(style: .continuous)
                        .fill(selected ? colors.accent : colors.fillSecondary)
                }
                .overlay {
                    if !selected {
                        Capsule(style: .continuous)
                            .stroke(colors.border.opacity(0.45), lineWidth: ExperienceBorder.hairline)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("tradeRooms.discovery.scope.\(value.rawValue)")
    }
}
