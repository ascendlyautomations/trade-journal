import SwiftUI

/// Per-room push preferences, web `RoomNotificationSettingsSheet` parity.
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
                            SettingsToggleRow(
                                title: channel.name,
                                subtitle: nil,
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
                        IndividualSubRoomsNotificationSectionHeader()
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
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("tradeRooms.notifications.done")
                }
            }
            .overlay {
                if viewModel.phase == .loading && viewModel.channelPrefs.isEmpty {
                    ExperienceIndeterminateProgress()
                }
            }
        }
        .onAppear { viewModel.loadIfNeeded() }
        .accessibilityIdentifier("tradeRooms.notifications.settings")
    }
}

// MARK: - Section header

private struct IndividualSubRoomsNotificationSectionHeader: View {
    private static let infoBody =
        "Each switch controls push alerts for that sub-room when room notifications are on. Turn off sub-rooms you do not want. If room notifications are off, change these after you turn the room back on."

    private let title = "Individual Sub-Rooms"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.xxs) {
            Text(title)
            AnalyticsMetricInfoButton(
                title: title,
                bodyText: Self.infoBody,
                accessibilityID: "tradeRooms.notifications.subRoomsSectionInfo"
            )
        }
        .textCase(nil)
    }
}