import SwiftUI

/// Compact horizontal channel list under the Trade Room header, with optional full-list popover.
struct RoomChannelSwitcherView: View {
    let channels: [RoomChannel]
    let selectedChannelID: RoomChannelID?
    let onSelect: (RoomChannelID) -> Void
    var showsExpandHeaderControl: Bool = false
    var onExpandHeader: (() -> Void)? = nil

    @State private var showsChannelPicker = false

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: ExperienceSpacing.xxs) {
            Button {
                showsChannelPicker = true
            } label: {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(colors.secondaryText)
                    .frame(width: 32, height: 28)
            }
            .buttonStyle(.experiencePlain)
            .accessibilityLabel("All sub-rooms")
            .accessibilityIdentifier("tradeRooms.channelSwitcher.menu")
            .popover(isPresented: $showsChannelPicker, arrowEdge: .top) {
                TradeRoomChannelPickerPopover(
                    channels: channels,
                    selectedChannelID: selectedChannelID
                ) { channelID in
                    showsChannelPicker = false
                    onSelect(channelID)
                }
                .presentationCompactAdaptation(.popover)
            }

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
                        .buttonStyle(.experiencePlain)
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                        .accessibilityIdentifier("tradeRooms.channel.\(channel.id.rawValue)")
                    }
                }
                .padding(.vertical, 4)
            }
            .layoutPriority(1)

            if showsExpandHeaderControl, let onExpandHeader {
                Button(action: onExpandHeader) {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(colors.secondaryText)
                        .frame(width: 32, height: 28)
                }
                .buttonStyle(.experiencePlain)
                .accessibilityLabel("Expand room header")
                .accessibilityIdentifier("tradeRooms.channelSwitcher.expandHeader")
            }
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.vertical, ExperienceSpacing.xxs)
        .accessibilityIdentifier("tradeRooms.channelSwitcher")
    }
}