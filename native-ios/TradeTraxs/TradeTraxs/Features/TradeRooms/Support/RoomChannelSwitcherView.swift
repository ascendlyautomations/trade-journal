import SwiftUI

/// Compact horizontal channel list under the Trade Room header.
struct RoomChannelSwitcherView: View {
    let channels: [RoomChannel]
    let selectedChannelID: RoomChannelID?
    let onSelect: (RoomChannelID) -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ExperienceSpacing.xs) {
                ForEach(channels) { channel in
                    let isSelected = channel.id == selectedChannelID
                    Button {
                        onSelect(channel.id)
                    } label: {
                        Text(channel.displayTitle)
                            .experienceStyle(
                                .caption,
                                color: isSelected ? colors.primaryBackground : colors.primaryText
                            )
                            .padding(.horizontal, ExperienceSpacing.sm)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isSelected ? colors.accent : colors.fillSecondary)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    .accessibilityIdentifier("tradeRooms.channel.\(channel.id.rawValue)")
                }
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.vertical, 4)
        }
        .accessibilityIdentifier("tradeRooms.channelSwitcher")
    }
}
