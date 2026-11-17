import SwiftUI

// MARK: - Channel list (subroom bar chevron)

struct TradeRoomChannelPickerPopover: View {
    let channels: [RoomChannel]
    let selectedChannelID: RoomChannelID?
    let onSelect: (RoomChannelID) -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(channels) { channel in
                    Button {
                        onSelect(channel.id)
                    } label: {
                        TradeRoomCompactPickerRow(
                            title: channel.displayTitle,
                            subtitle: channel.allowMembersChat ? nil : "Moderators only",
                            isSelected: channel.id == selectedChannelID
                        )
                    }
                    .buttonStyle(.experiencePlain)
                    if channel.id != channels.last?.id {
                        ExperienceDivider()
                            .padding(.leading, ExperienceSpacing.md)
                    }
                }
            }
            .padding(.vertical, ExperienceSpacing.xs)
        }
        .frame(minWidth: 220, maxHeight: 320)
        .background(colors.surfacePrimary)
    }
}

// MARK: - Trade Room membership switcher (nav bar)

struct TradeRoomMembershipPickerPopover: View {
    let rooms: [ExploreRoomSuggestion]
    let currentRoomID: RoomID
    let onSelect: (RoomID) -> Void

    @Environment(\.themeColors) private var colors
    @Bindable private var favoritesStore = TradeRoomFavoritesStore.shared

    var body: some View {
        Group {
            if rooms.isEmpty {
                Text("No rooms yet")
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(ExperienceSpacing.md)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rooms) { room in
                            Button {
                                onSelect(room.id)
                            } label: {
                                TradeRoomCompactPickerRow(
                                    title: room.name,
                                    subtitle: room.isOfficial ? "Official" : nil,
                                    isSelected: RoomNavigationFocusStore.shared.sameRoom(
                                        room.id,
                                        currentRoomID
                                    ),
                                    showsFavoriteStar: favoritesStore.isFavorited(room.id)
                                        || room.viewerIsFavorited
                                )
                            }
                            .buttonStyle(.experiencePlain)
                            if room.id != rooms.last?.id {
                                ExperienceDivider()
                                    .padding(.leading, ExperienceSpacing.md)
                            }
                        }
                    }
                    .padding(.vertical, ExperienceSpacing.xs)
                }
            }
        }
        .frame(minWidth: 240, maxHeight: 360)
        .background(colors.surfacePrimary)
    }
}

// MARK: - Shared row chrome

private struct TradeRoomCompactPickerRow: View {
    let title: String
    var subtitle: String?
    let isSelected: Bool
    var showsFavoriteStar: Bool = false

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title)
                        .experienceStyle(.subheadline, color: colors.primaryText)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .lineLimit(1)
                    if showsFavoriteStar {
                        Image(systemName: "star.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(colors.accent)
                            .accessibilityLabel("Favorited")
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .experienceStyle(.caption, color: colors.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: ExperienceSpacing.xs)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(colors.accent)
            }
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.vertical, ExperienceSpacing.sm)
        .contentShape(Rectangle())
        .background(isSelected ? colors.accent.opacity(0.12) : Color.clear)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}