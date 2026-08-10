import SwiftUI

struct SettingsTradingAccountsView: View {
    @State private var viewModel: SettingsTradingAccountsViewModel
    var propFirmOnly: Bool = false

    @Environment(\.themeColors) private var colors

    init(data: DataEnvironment, propFirmOnly: Bool = false) {
        _viewModel = State(
            initialValue: SettingsTradingAccountsViewModel(
                trades: data.trades,
                session: data.session
            )
        )
        self.propFirmOnly = propFirmOnly
    }

    init(viewModel: SettingsTradingAccountsViewModel, propFirmOnly: Bool = false) {
        _viewModel = State(initialValue: viewModel)
        self.propFirmOnly = propFirmOnly
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

            let rows = propFirmOnly ? viewModel.propAccounts : viewModel.accounts
            if rows.isEmpty, !viewModel.isLoading {
                Section {
                    Text(propFirmOnly ? "No prop firm accounts yet." : "No trading accounts yet.")
                        .experienceStyle(.body, color: colors.secondaryText)
                }
            } else {
                Section(propFirmOnly ? "Prop Firm Accounts" : "Accounts") {
                    ForEach(rows) { account in
                        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                            Text(account.name)
                                .experienceStyle(.body, color: colors.primaryText)
                            Text(subtitle(for: account))
                                .experienceStyle(.footnote, color: colors.secondaryText)
                        }
                        .padding(.vertical, ExperienceSpacing.xxs)
                        .accessibilityIdentifier("settings.account.\(account.id.rawValue)")
                    }
                }
            }

            Section {
                Text(
                    propFirmOnly
                        ? "Rule configuration editing arrives with the Prop Firm Settings phase. Analytics remain on Dashboard / Prop Firm Details."
                        : "Account creation and copy-trading group management remain on the web Trading Accounts settings for now. This screen is for review and configuration entry."
                )
                .experienceStyle(.footnote, color: colors.secondaryText)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(colors.groupedBackground.ignoresSafeArea())
        .navigationTitle(propFirmOnly ? "Prop Firm" : "Trading Accounts")
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .onAppear { viewModel.loadIfNeeded() }
        .accessibilityIdentifier(propFirmOnly ? "settings.propFirm" : "settings.tradingAccounts")
    }

    private func subtitle(for account: TradingAccount) -> String {
        var parts: [String] = []
        parts.append(account.category == .propFirm ? "Prop Firm" : account.category.rawValue.capitalized)
        parts.append(account.mode.rawValue.capitalized)
        if let size = account.size {
            parts.append(size.amount.formatted(.number.precision(.fractionLength(0))))
        }
        if !account.isActive {
            parts.append("Inactive")
        }
        return parts.joined(separator: " · ")
    }
}
