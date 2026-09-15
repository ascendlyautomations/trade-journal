import SwiftUI

/// Compact Dashboard entry for manual broker trade import (linked accounts only).
struct DashboardBrokerImportCard: View {
    @Bindable var store: BrokerImportEligibilityStore
    let onTap: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        DashboardQuickActionRow(
            title: "Import From Broker",
            subtitle: subtitle,
            accessibilityIdentifier: "dashboard.brokerImport",
            accessibilityHint: subtitle,
            icon: {
                ZStack {
                    Circle()
                        .fill(colors.accent.opacity(0.12))
                        .frame(
                            width: DashboardQuickActionStyle.iconDiameter,
                            height: DashboardQuickActionStyle.iconDiameter
                        )
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(colors.accent)
                }
            },
            onTap: onTap
        )
    }

    private var subtitle: String {
        let accounts = store.linkedAccounts
        guard !accounts.isEmpty else {
            return "Import new trades from your connected broker"
        }
        if accounts.count == 1, let account = accounts.first {
            let provider = BrokerIntegrationDisplay.providerLabel(account.provider)
            return "Import new trades from \(provider)"
        }
        let providers = Set(accounts.map(\.provider))
        if providers.count == 1, let provider = providers.first {
            return "Import new trades from \(BrokerIntegrationDisplay.providerLabel(provider))"
        }
        return "Import new trades from your connected brokers"
    }
}
