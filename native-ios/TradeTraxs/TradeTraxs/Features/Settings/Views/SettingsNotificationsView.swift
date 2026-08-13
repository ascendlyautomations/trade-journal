import SwiftUI

struct SettingsNotificationsView: View {
    @State private var viewModel: SettingsNotificationsViewModel
    var category: NotificationPreferenceCategory?

    @Environment(\.themeColors) private var colors

    init(
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator,
        category: NotificationPreferenceCategory? = nil
    ) {
        _viewModel = State(
            initialValue: SettingsNotificationsViewModel(
                repository: data.notificationPreferences,
                session: data.session,
                navigationCoordinator: navigationCoordinator
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
        .accessibilityIdentifier(
            category.map { "settings.notifications.\($0.rawValue)" } ?? "settings.notifications"
        )
    }

    @ViewBuilder
    private var rootContent: some View {
        Section {
            SettingsToggleRow(
                title: NotificationPreferenceKey.notificationsEnabled.title,
                subtitle: "Master switch for TradeTraxs notifications",
                isOn: Binding(
                    get: { viewModel.binding(for: .notificationsEnabled) },
                    set: { viewModel.set(.notificationsEnabled, enabled: $0) }
                )
            )
        }

        Section("Categories") {
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
                    viewModel.openCategory(category)
                } label: {
                    SettingsNavigationRow(title: category.title, systemImage: icon(for: category))
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.masterEnabled)
            }
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
