import SwiftUI
import UIKit

/// Local TradeTraxs reminder toggles (check-in + trade import), separate from server push categories.
struct SettingsTradetraxsRemindersView: View {
    @State private var viewModel: SettingsNotificationsViewModel

    @Environment(\.themeColors) private var colors

    init(
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator,
        pushNotifications: PushNotificationCenter? = nil
    ) {
        _viewModel = State(
            initialValue: SettingsNotificationsViewModel(
                repository: data.notificationPreferences,
                session: data.session,
                navigationCoordinator: navigationCoordinator,
                pushNotifications: pushNotifications
            )
        )
    }

    init(viewModel: SettingsNotificationsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        List {
            if viewModel.showsOpenSystemSettings || viewModel.showsRequestSystemNotificationAuthorization {
                Section {
                    if viewModel.showsRequestSystemNotificationAuthorization {
                        Button {
                            Task { await viewModel.requestSystemNotificationAuthorization() }
                        } label: {
                            SettingsNavigationRow(
                                title: "Allow Notifications",
                                subtitle: nil,
                                systemImage: "bell.badge",
                                showsChevron: false
                            )
                        }
                        .buttonStyle(.experiencePlain)
                    }
                    if viewModel.showsOpenSystemSettings {
                        Button {
                            viewModel.openSystemSettings()
                        } label: {
                            SettingsNavigationRow(
                                title: "Open iOS Settings",
                                subtitle: nil,
                                systemImage: "gear",
                                showsChevron: true
                            )
                        }
                        .buttonStyle(.experiencePlain)
                    }
                } header: {
                    Text("iOS Permissions")
                } footer: {
                    Text(remindersPermissionFooter)
                }
            }

            Section {
                SettingsToggleRow(
                    title: "Daily Check-In Reminder",
                    subtitle: "Weekday reminder at 9:15 AM in your local time zone.",
                    isOn: Binding(
                        get: { viewModel.dailyCheckInReminderOn },
                        set: { viewModel.setDailyCheckInReminderEnabled($0) }
                    ),
                    isEnabled: viewModel.isLocalReminderToggleInteractive
                )
                .accessibilityIdentifier("settings.notifications.dailyCheckInReminder")
            } header: {
                Text("Daily Check-In")
            }

            Section {
                SettingsToggleRow(
                    title: "Trade Import Reminders",
                    subtitle: "11:15 AM and 4:00 PM Eastern on trading days.",
                    isOn: Binding(
                        get: { viewModel.tradeImportReminderOn },
                        set: { viewModel.setTradeImportReminderEnabled($0) }
                    ),
                    isEnabled: viewModel.isLocalReminderToggleInteractive
                )
                .accessibilityIdentifier("settings.notifications.tradeImportReminder")
            } header: {
                Text("Trade Journal")
            }
        }
        .experienceInsetGroupedListStyle(pageBackground: true)
        .listSectionSpacing(ExperienceSpacing.sm)
        .experienceNavigationTitle("TradeTraxs Reminders")
        .onAppear {
            viewModel.loadIfNeeded()
            Task { await viewModel.refreshSystemAuthorization() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await viewModel.refreshSystemAuthorization() }
        }
        .accessibilityIdentifier("settings.notifications.tradetraxsReminders")
    }

    private var remindersPermissionFooter: String {
        if viewModel.showsRequestSystemNotificationAuthorization {
            return "TradeTraxs needs iOS notification permission to schedule local reminders. Turn on a reminder below or tap Allow Notifications."
        }
        if viewModel.showsOpenSystemSettings {
            return "Notifications are turned off for TradeTraxs in iOS Settings. Enable them to use local reminders."
        }
        return ""
    }
}