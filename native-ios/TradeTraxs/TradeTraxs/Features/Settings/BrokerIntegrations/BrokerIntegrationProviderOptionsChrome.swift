import SwiftUI

/// Shared layout for broker provider pickers (onboarding cards, integration sheets).
enum BrokerIntegrationProviderOptionsLayout {
    /// ~Half of the prior 12pt gap between provider cards.
    static let cardSpacing = ExperienceSpacing.xs
    static let footerTopPadding = ExperienceSpacing.sm
    static let groupVerticalPadding = ExperienceSpacing.xs
    /// Tighter spacing between grouped provider sections in ``BrokerIntegrationsView``.
    static let listSectionSpacing = ExperienceSpacing.xs
}

struct BrokerIntegrationComingSoonFooter: View {
    @Environment(\.themeColors) private var colors

    var body: some View {
        Text("More integrations coming soon!")
            .experienceStyle(.footnote, color: colors.tertiaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, BrokerIntegrationProviderOptionsLayout.footerTopPadding)
            .padding(.bottom, ExperienceSpacing.xxs)
            .accessibilityIdentifier("brokerIntegrations.comingSoon")
    }
}

/// Card-style connect control — onboarding and compact broker chooser surfaces.
struct BrokerIntegrationProviderConnectCard: View {
    let provider: BrokerIntegrationProvider
    var isDisabled = false
    let action: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Button(action: action) {
            HStack(spacing: ExperienceSpacing.sm) {
                Text("Connect \(BrokerIntegrationsCatalog.displayName(for: provider))")
                    .font(ExperienceTypography.headline)
                    .foregroundStyle(colors.primaryText)
                Spacer(minLength: ExperienceSpacing.sm)
                Image(systemName: "link")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(colors.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: ExperienceAccessibility.minTouchTarget)
            .padding(.horizontal, ExperienceSpacing.md)
            .background(colors.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous)
                    .stroke(colors.border, lineWidth: ExperienceBorder.thin)
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityIdentifier("brokerIntegrations.connectCard.\(provider.rawValue)")
    }
}

struct BrokerIntegrationProviderConnectOptionsStack: View {
    let providers: [BrokerIntegrationProvider]
    var isConnectDisabled: (BrokerIntegrationProvider) -> Bool = { _ in false }
    let onConnect: (BrokerIntegrationProvider) -> Void
    var showsComingSoonFooter = true

    var body: some View {
        VStack(spacing: BrokerIntegrationProviderOptionsLayout.cardSpacing) {
            ForEach(providers, id: \.self) { provider in
                BrokerIntegrationProviderConnectCard(
                    provider: provider,
                    isDisabled: isConnectDisabled(provider)
                ) {
                    onConnect(provider)
                }
            }
            if showsComingSoonFooter {
                BrokerIntegrationComingSoonFooter()
            }
        }
        .padding(.vertical, BrokerIntegrationProviderOptionsLayout.groupVerticalPadding)
    }
}
