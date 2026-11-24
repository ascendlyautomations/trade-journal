import SwiftUI

struct TradingPreferenceDiscoveryBanner: View {
    var placement: PreferenceDiscoveryPlacement
    var onPersonalize: () -> Void
    var onSkip: () -> Void
    var onSetup: () -> Void
    var onDismiss: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        switch placement {
        case .firstTrade:
            firstTradeCard
        case .quiet:
            quietBanner
        }
    }

    private var firstTradeCard: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Personalize Your Analytics")
                .experienceStyle(.headline, color: colors.primaryText)
            Text("Setting your personal trading rules improves performance insights and recommendations.")
                .experienceStyle(.subheadline, color: colors.secondaryText)
            HStack(spacing: ExperienceSpacing.sm) {
                Button("Personalize", action: onPersonalize)
                    .buttonStyle(.borderedProminent)
                Button("Maybe Later", action: onSkip)
                    .buttonStyle(.bordered)
            }
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceDashboardCard(cornerRadius: ExperienceRadius.card)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("analyticsPreferences.invite")
    }

    private var quietBanner: some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                Text("Get insights based on your trading rules.")
                    .experienceStyle(.subheadline, color: colors.primaryText)
                Button("Set Up Preferences", action: onSetup)
                    .font(.subheadline.weight(.semibold))
            }
            Spacer(minLength: ExperienceSpacing.sm)
            Button("Dismiss", action: onDismiss)
                .font(.subheadline)
                .foregroundStyle(colors.secondaryText)
                .accessibilityLabel("Dismiss analytics preferences invitation")
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceDashboardNestedCard(cornerRadius: ExperienceRadius.sm)
        .accessibilityIdentifier("analyticsPreferences.banner")
    }
}

/// Reports entry point when no trading rules are configured, uses shared discovery + preference cache.
struct ReportsConfigureTradingRulesPrompt: View {
    var userID: ProfileID?
    var repository: (any TradingPreferencesRepository)?
    var navigationCoordinator: NavigationCoordinator

    @Environment(\.themeColors) private var colors
    @Bindable private var store = TradingPreferenceDiscoveryStore.shared

    private var shouldShow: Bool {
        store.ready && !store.hasConfiguredRules && !store.configured
    }

    var body: some View {
        Group {
            if shouldShow {
                Button(action: openTradingRulesSettings) {
                    HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
                        Image(systemName: "checklist")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(colors.accent)
                            .frame(width: 28, height: 28)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Set Up Trading Rules")
                                .experienceStyle(.headline, color: colors.primaryText)
                                .multilineTextAlignment(.leading)
                            Text(
                                "Set your trading rules to unlock personalized compliance and discipline analytics."
                            )
                            .experienceStyle(.footnote, color: colors.secondaryText)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: ExperienceSpacing.xs)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(colors.tertiaryText)
                    }
                    .padding(ExperienceSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .experienceDashboardCard(cornerRadius: ExperienceRadius.card)
                    .overlay {
                        RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                            .stroke(colors.border, lineWidth: 1)
                    }
                }
                .buttonStyle(.experiencePlain)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("reports.configureTradingRules")
            }
        }
        .task(id: userID?.rawValue) {
            guard let userID, let repository else { return }
            await store.refresh(userID: userID, repository: repository)
        }
        .onReceive(NotificationCenter.default.publisher(for: .tradingPreferencesDidChange)) { _ in
            guard let userID, let repository else { return }
            Task { await store.refresh(userID: userID, repository: repository) }
        }
    }

    private func openTradingRulesSettings() {
        navigationCoordinator.pushHome(.settings(.tradingAnalytics))
    }
}

struct TradingPreferenceDiscoverySlot: View {
    enum Surface {
        case dashboard
        case analytics
    }

    var surface: Surface
    var userID: ProfileID?
    var repository: (any TradingPreferencesRepository)?
    var localHasTrade: Bool
    var navigationCoordinator: NavigationCoordinator

    var body: some View {
        let tour = ContextualTourCoordinator.shared.analyticsPreferenceTourGate()
        let store = TradingPreferenceDiscoveryStore.shared
        let placement = store.placement(
            tourEligible: tour.eligible,
            tourSettled: tour.settled,
            tourBlocking: tour.blocking,
            hasTrade: localHasTrade
        )
        let shown: PreferenceDiscoveryPlacement? = {
            switch surface {
            case .dashboard:
                if placement == .quiet, store.holdQuietDashboard { return nil }
                return placement
            case .analytics:
                return placement == .quiet ? .quiet : nil
            }
        }()
        Group {
            if let shown {
                TradingPreferenceDiscoveryBanner(
                    placement: shown,
                    onPersonalize: openPreferencesAfterInvite,
                    onSkip: { Task { await store.record(.skipped) } },
                    onSetup: openPreferences,
                    onDismiss: { Task { await store.record(.dismissed) } }
                )
            }
        }
        .task(id: userID?.rawValue) {
            guard let userID, let repository else { return }
            await store.refresh(userID: userID, repository: repository)
        }
    }

    private func openPreferences() {
        navigationCoordinator.pushHome(.settings(.tradingAnalytics))
    }

    private func openPreferencesAfterInvite() {
        Task { await TradingPreferenceDiscoveryStore.shared.record(.skipped) }
        openPreferences()
    }
}
