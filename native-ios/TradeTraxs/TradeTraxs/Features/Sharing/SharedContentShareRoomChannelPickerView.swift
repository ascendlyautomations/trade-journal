import SwiftUI

struct SharedContentShareRoomChannelPickerView: View {
    let room: TradeRoom
    let channels: [RoomChannel]
    var isLoadingChannels: Bool = false
    var selectedChannelID: RoomChannelID?
    let onSelect: (RoomChannel) -> Void
    let onCancel: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        NavigationStack {
            Group {
                if isLoadingChannels, channels.isEmpty {
                    ExperienceLoadingSpinner(label: "Loading sub-rooms")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if channels.isEmpty {
                    ExperienceEmptyState(
                        icon: .rooms,
                        title: "No sub-rooms",
                        message: "You can't post in any sub-room here."
                    )
                } else {
                    channelList
                }
            }
            .experienceScreenBackground()
            .navigationTitle("Choose sub-room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(colors.navigationBackground, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Text(room.name)
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ExperienceSpacing.sm)
                    .experienceChromeBarBackground()
                    .overlay(alignment: .bottom) {
                        Divider()
                    }
            }
        }
        .experienceSheetChrome()
    }

    private var channelList: some View {
        List(channels) { channel in
            Button {
                onSelect(channel)
            } label: {
                ShareRecipientSubRoomRow(
                    channel: channel,
                    isSelected: selectedChannelID == channel.id
                )
            }
            .buttonStyle(.plain)
            .experienceDashboardListRow()
            .accessibilityIdentifier("sharedContentShare.roomChannel.\(channel.id.rawValue)")
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .experienceDashboardGroupedRows()
        .listRowSeparatorTint(colors.separator)
    }
}

/// Sub-room destination row for internal share — matches DM / Trade Room selection styling.
struct ShareRecipientSubRoomRow: View {
    let channel: RoomChannel
    var isSelected: Bool = false

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.displayTitle)
                    .experienceStyle(.headline, color: colors.primaryText)
                    .lineLimit(1)
                if !channel.allowMembersChat {
                    Text("Owners only")
                        .experienceStyle(.caption, color: colors.secondaryText)
                }
            }
            Spacer(minLength: 0)
            selectionMark
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var selectionMark: some View {
        ZStack {
            Circle()
                .stroke(isSelected ? colors.accent : colors.border, lineWidth: isSelected ? 0 : 1.5)
                .frame(width: 24, height: 24)
            if isSelected {
                Circle()
                    .fill(colors.accent)
                    .frame(width: 24, height: 24)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(colors.onAccent)
            }
        }
        .accessibilityHidden(true)
    }
}
