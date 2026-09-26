import SwiftUI
import UIKit

/// Local TradeTraxs reminder toggles (check-in + trade import) — separate from server push categories.
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
            Section {
                SettingsToggleRow(
                    title: "Daily Check-In Reminder",
                    subtitle: "Weekday reminder at 9:15 AM in your local time zone.",
                    isOn: Binding(
                        get: { viewModel.dailyCheckInReminderEnabled },
                        set: { viewModel.setDailyCheckInReminderEnabled($0) }
                    ),
                    isEnabled: viewModel.systemAuthorization.isEnabled
                )
                .accessibilityIdentifier("settings.notifications.dailyCheckInReminder")
            } header: {
                Text("Daily Check-In")
            } footer: {
                if !viewModel.systemAuthorization.isEnabled {
                    Text("Turn on iOS notifications to receive check-in reminders.")
                }
            }

            Section {
                SettingsToggleRow(
                    title: "Trade Import Reminders",
                    subtitle: "11:15 AM and 4:00 PM Eastern on trading days.",
                    isOn: Binding(
                        get: { viewModel.tradeImportReminderEnabled },
                        set: { viewModel.setTradeImportReminderEnabled($0) }
                    ),
                    isEnabled: viewModel.systemAuthorization.isEnabled
                )
                .accessibilityIdentifier("settings.notifications.tradeImportReminder")
            } header: {
                Text("Trade Journal")
            } footer: {
                if !viewModel.systemAuthorization.isEnabled {
                    Text("Turn on iOS notifications to receive trade import reminders.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .experienceDashboardGroupedRows()
        .listSectionSpacing(ExperienceSpacing.sm)
        .scrollContentBackground(.hidden)
        .background(colors.groupedBackground.ignoresSafeArea())
        .experienceNavigationTitle("TradeTraxs Reminders")
        .onAppear { viewModel.loadIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await viewModel.refreshSystemAuthorization() }
        }
        .accessibilityIdentifier("settings.notifications.tradetraxsReminders")
    }
}
