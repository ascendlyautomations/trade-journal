import SwiftUI

struct SettingsSubscriptionView: View {
    @State private var viewModel: SettingsSubscriptionViewModel

    @Environment(\.themeColors) private var colors

    private static let dateStyle = Date.FormatStyle(date: .abbreviated, time: .omitted)

    init(data: DataEnvironment, navigationCoordinator: NavigationCoordinator) {
        _viewModel = State(
            initialValue: SettingsSubscriptionViewModel(
                billing: data.billing,
                session: data.session,
                navigationCoordinator: navigationCoordinator
            )
        )
    }

    init(viewModel: SettingsSubscriptionViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        List {
            if let error = viewModel.errorMessage {
                Section {
                    SettingsInlineError(message: error) {
                        Task { await viewModel.refresh() }
                    }
                }
            }

            Section {
                SettingsInfoRow(title: "Plan", value: viewModel.planTitle)
                SettingsInfoRow(title: "Status", value: viewModel.statusTitle)
                if let interval = viewModel.status?.billingInterval {
                    SettingsInfoRow(title: "Billing", value: intervalLabel(interval))
                }
                if let trial = viewModel.status?.trialEndsAt {
                    SettingsInfoRow(title: "Trial ends", value: trial.formatted(Self.dateStyle))
                }
                if let renews = viewModel.status?.currentPeriodEndsAt {
                    SettingsInfoRow(
                        title: viewModel.status?.cancelAtPeriodEnd == true ? "Ends" : "Renews",
                        value: renews.formatted(Self.dateStyle)
                    )
                }
            } header: {
                Text("Current Plan")
            } footer: {
                Text("Manage your current membership.")
            }

            if let status = viewModel.status, !status.isProEntitled || status.lifecycle == .trialing {
                Section {
                    Button {
                        viewModel.openUpgrade()
                    } label: {
                        SettingsPrimaryActionLabel(title: "Upgrade to TraxPro", systemImage: "sparkles")
                    }
                    .buttonStyle(.plain)
                } footer: {
                    Text("Unlock higher limits and TraxPro features.")
                }
            }

            if let status = viewModel.status, !status.isProEntitled {
                Section {
                    if let trades = status.dailyTradeLimit {
                        SettingsInfoRow(title: "Daily trades", value: "\(trades)")
                    }
                    if let posts = status.dailyPostLimit {
                        SettingsInfoRow(title: "Daily posts", value: "\(posts)")
                    }
                    if let messages = status.dailyMessageLimit {
                        SettingsInfoRow(title: "Daily messages", value: "\(messages)")
                    }
                    if let accounts = status.maxTradeEntryAccounts {
                        SettingsInfoRow(title: "Active accounts", value: "\(accounts)")
                    }
                } header: {
                    Text("Free Plan Limits")
                } footer: {
                    Text("These are your daily limits on the free plan.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(colors.groupedBackground.ignoresSafeArea())
        .experienceNavigationTitle("Subscription")
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .onAppear { viewModel.loadIfNeeded() }
        .accessibilityIdentifier("settings.subscription")
    }

    private func intervalLabel(_ interval: BillingInterval) -> String {
        switch interval {
        case .monthly: return "Monthly"
        case .sixMonth: return "6 months"
        case .yearly: return "Yearly"
        }
    }
}
