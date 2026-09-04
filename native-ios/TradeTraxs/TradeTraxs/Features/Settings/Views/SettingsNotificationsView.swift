import SwiftUI
import UIKit

struct SettingsNotificationsView: View {
    @State private var viewModel: SettingsNotificationsViewModel
    var category: NotificationPreferenceCategory?

    @Environment(\.stackNavigation) private var stackNavigation
    @Environment(\.themeColors) private var colors

    init(
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator,
        category: NotificationPreferenceCategory? = nil,
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
        self.category = category
    }

    init(viewModel: SettingsNotificationsViewModel, category: NotificationPreferenceCategory? = nil) {
        _viewModel = State(initialValue: viewModel)
        self.category = category
    }

    var body: some View {
        List {
            if let error = viewModel.saveError {
                Section {
                    SettingsInlineError(message: error) {
                        Task { await viewModel.refresh() }
                    }
                }
            }

            if let category {
                categorySection(category)
            } else {
                rootContent
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(colors.groupedBackground.ignoresSafeArea())
        .experienceNavigationTitle(category?.title ?? "Notifications")
        .overlay {
            if viewModel.phase == .loading && viewModel.preferences == nil {
                ProgressView()
            }
        }
        .onAppear { viewModel.loadIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await viewModel.refreshSystemAuthorization() }
        }
        .accessibilityIdentifier(
            category.map { "settings.notifications.\($0.rawValue)" } ?? "settings.notifications"
        )
    }

    @ViewBuilder
    private var rootContent: some View {
        Section {
            SettingsInfoRow(title: "iOS Permission", value: viewModel.systemPushStatusLabel)
            if viewModel.showsOpenSystemSettings {
                Button {
                    viewModel.openSystemSettings()
                } label: {
                    SettingsNavigationRow(
                        title: "Open iOS Settings",
                        subtitle: "Enable notifications for TradeTraxs",
                        systemImage: "gear"
                    )
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Device")
        } footer: {
            Text("This is your phone’s permission. It’s separate from the preferences below.")
        }

        Section {
            SettingsToggleRow(
                title: "Daily Check-In Reminder",
                subtitle: "Remind me before the market opens if I haven't completed my daily check-in.",
                isOn: Binding(
                    get: { viewModel.dailyCheckInReminderEnabled },
                    set: { viewModel.setDailyCheckInReminderEnabled($0) }
                ),
                isEnabled: viewModel.systemAuthorization.isEnabled
            )
            .accessibilityIdentifier("settings.notifications.dailyCheckInReminder")
        } footer: {
            if viewModel.systemAuthorization.isEnabled {
                Text("Weekday reminders arrive at 9:15 AM in your local time zone.")
            } else {
                Text("Turn on iOS notifications to receive weekday check-in reminders at 9:15 AM.")
            }
        }

        Section {
            SettingsToggleRow(
                title: NotificationPreferenceKey.notificationsEnabled.title,
                subtitle: NotificationPreferenceKey.notificationsEnabled.subtitle,
                isOn: Binding(
                    get: { viewModel.binding(for: .notificationsEnabled) },
                    set: { viewModel.set(.notificationsEnabled, enabled: $0) }
                )
            )
        } header: {
            Text("Notifications")
        } footer: {
            Text("Choose which notifications you’d like to receive.")
        }

        Section {
            ForEach(
                [
                    NotificationPreferenceCategory.messages,
                    .social,
                    .rooms,
                    .achievements,
                    .product,
                ],
                id: \.self
            ) { category in
                Button {
                    ExperienceHaptics.play(.selection)
                    if let route = category.settingsRoute {
                        stackNavigation?.pushSettings(route)
                    }
                } label: {
                    SettingsNavigationRow(title: category.title, systemImage: icon(for: category))
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.masterEnabled)
                .accessibilityIdentifier("settings.notifications.category.\(category.rawValue)")
            }
        } header: {
            Text("Categories")
        } footer: {
            Text("Turn a category off to pause that type of alert.")
        }

        if case .failed(let message) = viewModel.phase {
            Section {
                SettingsInlineError(message: message) {
                    Task { await viewModel.refresh() }
                }
            }
        }
    }

    @ViewBuilder
    private func categorySection(_ category: NotificationPreferenceCategory) -> some View {
        Section {
            ForEach(category.keys, id: \.self) { key in
                SettingsToggleRow(
                    title: key.title,
                    subtitle: key.subtitle,
                    isOn: Binding(
                        get: { viewModel.binding(for: key) },
                        set: { viewModel.set(key, enabled: $0) }
                    ),
                    isEnabled: viewModel.masterEnabled || key == .notificationsEnabled
                )
            }
        } footer: {
            if !viewModel.masterEnabled {
                Text("Turn on Allow Notifications to deliver these categories.")
            } else {
                Text(category.sectionFooter)
            }
        }
    }

    private func icon(for category: NotificationPreferenceCategory) -> String {
        switch category {
        case .master: return "bell"
        case .messages: return "bubble.left.and.bubble.right"
        case .social: return "heart"
        case .rooms: return "person.3"
        case .achievements: return "trophy"
        case .product: return "megaphone"
        }
    }
}
