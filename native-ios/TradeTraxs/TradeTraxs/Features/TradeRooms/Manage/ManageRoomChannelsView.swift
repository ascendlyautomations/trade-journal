import SwiftUI

/// Manage Room → Channels — normal list + explicit Edit mode for permissions and channel admin.
struct ManageRoomChannelsView: View {
    @Bindable var viewModel: ManageRoomViewModel
    @Binding var editingChannel: RoomChannel?
    @Binding var showsCreateChannel: Bool

    @Environment(\.themeColors) private var colors
    @State private var isEditingChannels = false
    @State private var expandedChannelID: RoomChannelID?

    private var sortedChannels: [RoomChannel] {
        viewModel.channels.sorted { $0.position < $1.position }
    }

    var body: some View {
        List {
            Section {
                ForEach(Array(sortedChannels.enumerated()), id: \.element.id) { index, channel in
                    channelRow(channel: channel, index: index, total: sortedChannels.count)
                }
            }

            if isEditingChannels, viewModel.canManageRoom {
                if sortedChannels.count < RoomChannelValidation.maxCount {
                    Section {
                        Button {
                            showsCreateChannel = true
                        } label: {
                            Label("Create Channel", systemImage: "plus")
                        }
                        .disabled(viewModel.isMutatingChannel)
                    }
                }
            }

            if let statusMessage = viewModel.statusMessage {
                Section {
                    Text(statusMessage)
                        .experienceStyle(.footnote, color: colors.secondaryText)
                }
            }
        }
        .listStyle(.insetGrouped)
        .experienceDashboardGroupedRows()
        .scrollContentBackground(.hidden)
        .experienceNavigationTitle("Channels")
        .toolbar {
            if viewModel.canManageRoom {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditingChannels ? "Done" : "Edit") {
                        ExperienceHaptics.play(.selection)
                        if isEditingChannels {
                            expandedChannelID = nil
                            isEditingChannels = false
                        } else {
                            isEditingChannels = true
                        }
                    }
                    .fontWeight(isEditingChannels ? .semibold : .regular)
                    .accessibilityIdentifier(
                        isEditingChannels ? "tradeRooms.channels.done" : "tradeRooms.channels.edit"
                    )
                }
            }
        }
        .refreshable { await viewModel.refreshChannels() }
        .accessibilityIdentifier("tradeRooms.channels")
    }

    @ViewBuilder
    private func channelRow(channel: RoomChannel, index: Int, total: Int) -> some View {
        let isExpanded = isEditingChannels && expandedChannelID == channel.id
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            if isEditingChannels, viewModel.canManageRoom {
                Button {
                    toggleExpanded(channel.id)
                } label: {
                    channelHeader(channel: channel, showsDisclosure: true, chevronDown: isExpanded)
                }
                .buttonStyle(.plain)
            } else {
                channelHeader(channel: channel, showsDisclosure: false, chevronDown: false)
            }

            if isExpanded {
                permissionEditor(for: channel)
                channelManagementActions(channel: channel, index: index, total: total)
            }
        }
        .padding(.vertical, ExperienceSpacing.xxs)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if isEditingChannels, viewModel.canManageRoom {
                Button(role: .destructive) {
                    Task { await viewModel.requestDeleteChannel(channel) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(sortedChannels.count <= RoomChannelValidation.minCount)
            }
        }
    }

    private func channelHeader(
        channel: RoomChannel,
        showsDisclosure: Bool,
        chevronDown: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.displayTitle)
                    .experienceStyle(.body, color: colors.primaryText)
                Text(RoomChannelPostingPermission.from(allowMembersChat: channel.allowMembersChat).summaryLabel)
                    .experienceStyle(.caption, color: colors.secondaryText)
            }
            Spacer(minLength: 0)
            if viewModel.savingChannelPermissionID == channel.id {
                ProgressView()
                    .controlSize(.small)
            } else if showsDisclosure {
                Image(systemName: chevronDown ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(colors.tertiaryText)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func permissionEditor(for channel: RoomChannel) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("WHO CAN POST")
                .experienceStyle(.caption, color: colors.secondaryText)
                .padding(.top, ExperienceSpacing.xxs)

            let liveChannel = viewModel.channels.first(where: { $0.id == channel.id }) ?? channel
            let selected = RoomChannelPostingPermission.from(allowMembersChat: liveChannel.allowMembersChat)
            ForEach(RoomChannelPostingPermission.allCases, id: \.self) { option in
                Button {
                    Task {
                        await viewModel.setChannelPostingPermission(
                            liveChannel,
                            allowMembersChat: option.allowMembersChat
                        )
                    }
                } label: {
                    HStack(spacing: ExperienceSpacing.sm) {
                        Image(systemName: selected == option ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selected == option ? colors.accent : colors.tertiaryText)
                        Text(option.summaryLabel)
                            .experienceStyle(.body, color: colors.primaryText)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.savingChannelPermissionID == channel.id)
            }
        }
        .padding(.leading, ExperienceSpacing.xxs)
    }

    @ViewBuilder
    private func channelManagementActions(channel: RoomChannel, index: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Button("Rename Channel") {
                editingChannel = channel
            }
            .font(.subheadline)

            HStack(spacing: ExperienceSpacing.md) {
                if index > 0 {
                    Button("Move Up") {
                        Task { await viewModel.moveChannel(channel, direction: -1) }
                    }
                    .font(.subheadline)
                    .disabled(viewModel.isMutatingChannel)
                }
                if index < total - 1 {
                    Button("Move Down") {
                        Task { await viewModel.moveChannel(channel, direction: 1) }
                    }
                    .font(.subheadline)
                    .disabled(viewModel.isMutatingChannel)
                }
            }

            if total > RoomChannelValidation.minCount {
                Button("Delete Channel", role: .destructive) {
                    Task { await viewModel.requestDeleteChannel(channel) }
                }
                .font(.subheadline)
            }
        }
        .padding(.top, ExperienceSpacing.xs)
    }

    private func toggleExpanded(_ channelID: RoomChannelID) {
        if expandedChannelID == channelID {
            expandedChannelID = nil
        } else {
            expandedChannelID = channelID
        }
    }
}
