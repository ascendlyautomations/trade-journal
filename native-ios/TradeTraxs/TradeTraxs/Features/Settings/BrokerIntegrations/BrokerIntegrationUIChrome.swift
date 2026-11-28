import SwiftUI

struct BrokerAccountLinkContext: Equatable {
    let provider: BrokerIntegrationProvider
    let account: BrokerIntegrationAccount
}

// MARK: - Security disclaimer

struct BrokerIntegrationsSecurityDisclaimer: View {
    @Environment(\.themeColors) private var colors

    var body: some View {
        Text(
            "TradeTraxs connects to brokers through secure sign-in. Your passwords are not saved on this device."
        )
        .experienceStyle(.footnote, color: colors.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("brokerIntegrations.securityDisclaimer")
    }
}

// MARK: - Broker integrations list chrome

/// Tighter card padding for nested broker integration rows (Settings density).
struct BrokerIntegrationCompactCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    @Environment(\.themeColors) private var colors
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        content()
            .padding(ExperienceSpacing.sm)
            .experienceSurface(
                .card,
                cornerRadius: ExperienceRadius.card,
                elevation: .flat
            )
            .overlay {
                RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                    .stroke(borderColor, lineWidth: ExperienceBorder.hairline)
            }
    }

    private var borderColor: Color {
        if colorScheme == .light {
            return colors.border.opacity(ExperienceDashboardSurface.LightChrome.borderOpacity)
        }
        return colors.border.opacity(ExperienceOpacity.subtle)
    }
}

struct BrokerIntegrationSettingsButton: View {
    let title: String
    var icon: AppIcon? = nil
    var isPrimary = false
    var isDestructive = false
    var isEnabled = true
    var isLoading = false
    var accessibilityIdentifier: String? = nil
    let action: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Button(action: {
            guard isEnabled, !isLoading else { return }
            ExperienceHaptics.play(isDestructive ? .warning : .selection)
            action()
        }) {
            HStack(spacing: ExperienceSpacing.xxs) {
                if isLoading {
                    ExperienceIndeterminateProgress()
                        .controlSize(.small)
                } else if let icon {
                    ExperienceIcon(icon: icon, size: .sm, color: labelColor)
                }
                Text(title)
                    .font(ExperienceTypography.subheadline.weight(isPrimary ? .semibold : .medium))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, ExperienceSpacing.sm)
            .padding(.vertical, ExperienceSpacing.xs + 2)
            .background(background)
            .foregroundStyle(labelColor)
            .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous))
            .overlay {
                if !isPrimary, !isDestructive {
                    RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous)
                        .stroke(colors.border, lineWidth: ExperienceBorder.thin)
                }
            }
            .opacity(isEnabled ? ExperienceOpacity.opaque : ExperienceOpacity.disabled)
        }
        .buttonStyle(.experiencePlain)
        .disabled(!isEnabled || isLoading)
        .experienceAccessibility(
            label: title,
            identifier: accessibilityIdentifier,
            traits: .isButton
        )
    }

    private var labelColor: Color {
        if isDestructive { return colors.loss }
        if isPrimary { return colors.onAccent }
        return colors.primaryText
    }

    @ViewBuilder
    private var background: some View {
        if isPrimary {
            colors.accent
        } else {
            Color.clear
        }
    }
}

struct BrokerIntegrationTextAction: View {
    let title: String
    var isDestructive = false
    var isEnabled = true
    let action: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(ExperienceTypography.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(isDestructive ? colors.loss : colors.primaryText)
        }
        .buttonStyle(.experiencePlain)
        .disabled(!isEnabled)
    }
}

// MARK: - Discovered account summary (link / create flows)

struct BrokerDiscoveredAccountSummaryCard: View {
    let provider: BrokerIntegrationProvider
    let account: BrokerIntegrationAccount

    @Environment(\.themeColors) private var colors

    private var maskedNumber: String {
        BrokerIntegrationDisplay.maskedBrokerAccountNumber(
            account.externalAccountId,
            name: account.externalAccountName,
            displayName: account.externalDisplayName
        )
    }

    private var typeLabel: String? {
        BrokerIntegrationDisplay.brokerAccountTypeLabel(metadata: account.metadata)
    }

    private var subtitle: String? {
        let title = account.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let numberSource = account.externalAccountName ?? account.externalAccountId
        if title == numberSource || title == account.externalAccountId { return nil }
        return title
    }

    var body: some View {
        ExperienceCard {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                Text(BrokerIntegrationDisplay.providerLabel(provider))
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .textCase(.uppercase)
                HStack(alignment: .firstTextBaseline) {
                    Text(maskedNumber)
                        .font(ExperienceTypography.headline)
                        .foregroundStyle(colors.primaryText)
                    Spacer(minLength: ExperienceSpacing.xs)
                    if let typeLabel {
                        Text(typeLabel)
                            .experienceStyle(.subheadline, color: colors.secondaryText)
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .experienceStyle(.footnote, color: colors.tertiaryText)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("brokerIntegrations.brokerAccountSummary")
    }
}

// MARK: - Link-existing eligibility (Manage Accounts load state)

enum BrokerLinkEligibleAccountsPresentation: Equatable {
    case loading
    case failed(message: String)
    case empty
    case ready([TradingAccountID])

    static func resolve(
        isLoading: Bool,
        errorMessage: String?,
        accounts: [TradingAccount]
    ) -> BrokerLinkEligibleAccountsPresentation {
        if isLoading, accounts.isEmpty, errorMessage == nil {
            return .loading
        }
        if let errorMessage, accounts.isEmpty {
            return .failed(message: errorMessage)
        }
        if accounts.isEmpty {
            return .empty
        }
        return .ready(accounts.map(\.id))
    }

    func tradingAccounts(from all: [TradingAccount]) -> [TradingAccount] {
        guard case .ready(let ids) = self else { return [] }
        let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        return all.filter { order[$0.id] != nil }.sorted { lhs, rhs in
            (order[lhs.id] ?? 0) < (order[rhs.id] ?? 0)
        }
    }
}

struct BrokerLinkExistingAccountsSection: View {
    let presentation: BrokerLinkEligibleAccountsPresentation
    let accounts: [TradingAccount]
    @Binding var selectedAccountID: TradingAccountID?
    var onRetryLoad: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        switch presentation {
        case .loading:
            HStack(spacing: ExperienceSpacing.sm) {
                ExperienceIndeterminateProgress()
                    .controlSize(.small)
                Text("Loading your TradeTraxs accounts…")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("brokerIntegrations.linkAccount.loadingAccounts")

        case .failed(let message):
            VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                Text("Couldn't load accounts")
                    .experienceStyle(.subheadline, color: colors.primaryText)
                Text(message)
                    .experienceStyle(.footnote, color: colors.secondaryText)
                Button("Retry") {
                    onRetryLoad()
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.experiencePlain)
            }
            .accessibilityIdentifier("brokerIntegrations.linkAccount.loadFailed")

        case .empty:
            Text("No eligible accounts available")
                .experienceStyle(.subheadline, color: colors.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Create a new TradeTraxs account below to link this broker account.")
                .experienceStyle(.footnote, color: colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("brokerIntegrations.linkAccount.noEligible")

        case .ready:
            let selectable = presentation.tradingAccounts(from: accounts)
            ForEach(selectable) { account in
                BrokerLinkSelectableAccountRow(
                    account: account,
                    isSelected: selectedAccountID == account.id
                ) {
                    ExperienceHaptics.play(.selection)
                    selectedAccountID = account.id
                }
            }
        }
    }
}

struct BrokerLinkSelectableAccountRow: View {
    let account: TradingAccount
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: ExperienceSpacing.sm) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? colors.accent : colors.tertiaryText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                    Text(TradingAccountDisplay.title(for: account, audience: .owner))
                        .experienceStyle(.body, color: colors.primaryText)
                    Text(TradingAccountDisplay.ownerDropdownModeLabel(account.mode))
                        .experienceStyle(.footnote, color: colors.secondaryText)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.experiencePlain)
        .accessibilityIdentifier("brokerIntegrations.linkAccount.account.\(account.id.rawValue)")
    }
}

// MARK: - List card row wrapper

extension View {
    /// Full section-width card rows, same horizontal alignment as other Settings grouped sections.
    func brokerIntegrationsCardListRow() -> some View {
        self
            .listRowInsets(SettingsListLayout.groupedCardRowInsets)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}