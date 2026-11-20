import SwiftUI

/// Per-room push preferences — web `RoomNotificationSettingsSheet` parity.
struct RoomNotificationSettingsView: View {
    @State private var viewModel: RoomNotificationSettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors

    init(viewModel: RoomNotificationSettingsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            List {
                if let saveError = viewModel.saveError {
                    Section {
                        SettingsInlineError(message: saveError) {
                            Task { await viewModel.refresh() }
                        }
                    }
                }

                if case .failed(let message) = viewModel.phase {
                    Section {
                        SettingsInlineError(message: message) {
                            Task { await viewModel.refresh() }
                        }
                    }
                }

                Section {
                    SettingsToggleRow(
                        title: "Entire Trade Room",
                        subtitle: "Master switch for all channels in this room",
                        isOn: Binding(
                            get: { viewModel.roomNotificationsEnabled },
                            set: { viewModel.setRoomNotificationsEnabled($0) }
                        )
                    )
                    .accessibilityIdentifier("tradeRooms.notifications.roomMaster")
                }

                if !viewModel.channels.isEmpty {
                    Section {
                        ForEach(viewModel.channels) { channel in
                            RoomChannelNotificationToggleRow(
                                channelName: channel.name,
                                isOn: Binding(
                                    get: { viewModel.effectiveChannelNotificationsEnabled(channel.id) },
                                    set: { viewModel.setChannelNotificationsEnabled(channel.id, enabled: $0) }
                                ),
                                isEnabled: viewModel.roomNotificationsEnabled
                                    && !viewModel.isSavingChannel(channel.id)
                            )
                            .opacity(viewModel.roomNotificationsEnabled ? 1 : 0.55)
                            .accessibilityIdentifier("tradeRooms.notifications.channel.\(channel.id.rawValue)")
                        }
                    } header: {
                        Text("Individual Sub-Rooms")
                    }
                } else {
                    Section {
                        Text("This room has no sub-rooms. Room-level notifications apply to all messages.")
                            .experienceStyle(.footnote, color: colors.secondaryText)
                    }
                }
            }
            .experienceInsetGroupedListStyle(pageBackground: true)
            .listSectionSpacing(ExperienceSpacing.sm)
            .navigationTitle("Manage Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("tradeRooms.notifications.done")
                }
            }
            .overlay {
                if viewModel.phase == .loading && viewModel.channelPrefs.isEmpty {
                    ProgressView()
                }
            }
        }
        .onAppear { viewModel.loadIfNeeded() }
        .accessibilityIdentifier("tradeRooms.notifications.settings")
    }
}

// MARK: - Sub-room row

private struct RoomChannelNotificationToggleRow: View {
    let channelName: String
    @Binding var isOn: Bool
    var isEnabled: Bool = true

    @State private var showsInfo = false
    @Environment(\.themeColors) private var colors

    private var infoBody: String {
        """
        Controls push alerts for new messages in \(channelName). Turn this off to stop \
        notifications from this sub-room while room notifications stay on. When room \
        notifications are off, sub-room settings apply after you turn the room back on.
        """
    }

    var body: some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
            HStack(alignment: .center, spacing: ExperienceSpacing.xxs) {
                Text(channelName)
                    .experienceStyle(.body, color: colors.primaryText)
                    .lineLimit(2)
                Button {
                    showsInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(colors.tertiaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("About \(channelName) notifications")
                .accessibilityIdentifier("tradeRooms.notifications.channelInfo.\(channelName)")
                .popover(isPresented: $showsInfo) {
                    VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                        Text(channelName)
                            .font(ExperienceTypography.subheadline.weight(.semibold))
                            .foregroundStyle(colors.primaryText)
                        Text(infoBody)
                            .font(ExperienceTypography.footnote)
                            .foregroundStyle(colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(ExperienceSpacing.md)
                    .frame(width: 280, alignment: .leading)
                    .presentationCompactAdaptation(.popover)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!isEnabled)
        }
        .padding(.vertical, ExperienceSpacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.toggle.\(channelName)")
    }
}