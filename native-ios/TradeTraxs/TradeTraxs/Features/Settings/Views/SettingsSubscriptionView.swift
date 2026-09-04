import SwiftUI

struct SettingsSubscriptionView: View {
    @State private var viewModel: SettingsSubscriptionViewModel

    @Environment(\.themeColors) private var colors

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
            } footer: {
                Text(viewModel.membershipSummaryFooter)
            }

            if viewModel.showsFreePlanDetails, let status = viewModel.status {
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
                    Text("Included on Free")
                } footer: {
                    Text("These limits apply to your current Free membership.")
                }

                Section {
                    ForEach(viewModel.traxProFeatureHighlights, id: \.self) { feature in
                        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                            Image(systemName: "sparkles")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(colors.accent)
                                .frame(width: 20, alignment: .center)
                                .padding(.top, 2)
                            Text(feature)
                                .experienceStyle(.body, color: colors.primaryText)
                        }
                        .padding(.vertical, ExperienceSpacing.xxs)
                    }
                } header: {
                    Text("TraxPro Includes")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(colors.groupedBackground.ignoresSafeArea())
        .experienceNavigationTitle("Plan")
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .onAppear { viewModel.loadIfNeeded() }
        .accessibilityIdentifier("settings.subscription")
    }
}
