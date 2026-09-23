import SwiftUI

struct BrokerOnboardingView: View {
    let data: DataEnvironment
    let gateStore: ProfileOnboardingGateStore

    @State private var viewModel: BrokerIntegrationsViewModel
    @State private var manageAccountsViewModel: ManageAccountsViewModel
    @State private var linkTarget: BrokerIntegrationLinkTarget?
    @State private var createLinkTarget: BrokerIntegrationCreateLinkTarget?

    @Environment(\.themeColors) private var colors

    init(data: DataEnvironment, gateStore: ProfileOnboardingGateStore) {
        self.data = data
        self.gateStore = gateStore
        let manage = ManageAccountsViewModel(
            trades: data.trades,
            session: data.session,
            detailCache: data.detailCache
        )
        _manageAccountsViewModel = State(initialValue: manage)
        _viewModel = State(
            initialValue: BrokerIntegrationsViewModel(
                broker: data.brokerIntegrations,
                trades: data.trades,
                manageAccounts: manage,
                session: data.session,
                detailCache: data.detailCache
            )
        )
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                    header

                    if viewModel.hasActiveConnectedBroker {
                        connectedBrokersSection
                        if !allSupportedProvidersConnected {
                            connectAnotherBrokerSection
                        }
                    } else {
                        brokerConnectOptionsSection
                    }

                    if viewModel.unlinkedBrokerAccountsCount > 0 {
                        linkingHint
                    }
                    if let message = viewModel.oauthErrorMessage ?? nonOAuthActionMessage {
                        Text(message)
                            .experienceStyle(.footnote, color: colors.error)
                    }

                    optionalConnectLaterHint

                    if viewModel.hasActiveConnectedBroker {
                        continueButton
                    } else {
                        maybeLaterButton
                    }
                }
                .experiencePadding(.xl)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .experienceScreenBackground()

            BrokerIntegrationConnectionCoordinator(
                viewModel: viewModel,
                manageAccountsViewModel: manageAccountsViewModel,
                data: data,
                linkTarget: $linkTarget,
                createLinkTarget: $createLinkTarget,
                showsImportedTradesReview: false
            )
        }
        .onAppear {
            BrokerIntegrationsLoadPriorityGate.setScreenActive(true)
            manageAccountsViewModel.loadIfNeeded()
            Task { await viewModel.refreshAll() }
        }
        .onDisappear {
            BrokerIntegrationsLoadPriorityGate.setScreenActive(false)
        }
        .onChange(of: viewModel.unlinkedBrokerAccountsCount) { _, _ in
            promptLinkingIfNeeded()
        }
        .onChange(of: viewModel.hasActiveConnectedBroker) { _, _ in
            promptLinkingIfNeeded()
        }
        .accessibilityIdentifier("onboarding.broker")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text("TradeTraxs")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(colors.primaryText)

            Text("Connect Your Broker")
                .font(ExperienceTypography.callout)
                .fontWeight(.semibold)
                .foregroundStyle(colors.accent)

            Text("Automatically import your trades into TradeTraxs.")
                .experienceStyle(.body, color: colors.secondaryText)
        }
        .padding(.top, ExperienceSpacing.lg)
    }

    private var connectedProviderRows: [BrokerIntegrationProvider] {
        var rows: [BrokerIntegrationProvider] = []
        if viewModel.tradovateConnections.contains(where: \.connected) {
            rows.append(.tradovate)
        }
        if viewModel.rithmicConnections.contains(where: \.connected) {
            rows.append(.rithmic)
        }
        return rows
    }

    private var unconnectedSupportedProviders: [BrokerIntegrationProvider] {
        BrokerIntegrationsCatalog.providers.filter { provider in
            guard isProviderOfferedOnOnboarding(provider) else { return false }
            switch provider {
            case .tradovate:
                return !viewModel.tradovateConnections.contains(where: \.connected)
            case .rithmic:
                return !viewModel.rithmicConnections.contains(where: \.connected)
            }
        }
    }

    private var allSupportedProvidersConnected: Bool {
        unconnectedSupportedProviders.isEmpty
    }

    private func isProviderOfferedOnOnboarding(_ provider: BrokerIntegrationProvider) -> Bool {
        switch provider {
        case .tradovate:
            return true
        case .rithmic:
            return viewModel.showsRithmicBrokerOnboardingOption
        }
    }

    private var connectedBrokersSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            ForEach(connectedProviderRows, id: \.self) { provider in
                connectedBrokerRow(provider)
            }
        }
        .accessibilityIdentifier("onboarding.broker.connectedSection")
    }

    private func connectedBrokerRow(_ provider: BrokerIntegrationProvider) -> some View {
        HStack(spacing: ExperienceSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(colors.profit)
                .accessibilityHidden(true)

            Text(BrokerIntegrationsCatalog.displayName(for: provider))
                .font(ExperienceTypography.headline)
                .foregroundStyle(colors.primaryText)

            Spacer(minLength: ExperienceSpacing.sm)

            Text("Connected")
                .experienceStyle(.footnote, color: colors.secondaryText)
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
        .accessibilityIdentifier("onboarding.broker.connected.\(provider.rawValue)")
    }

    private var connectAnotherBrokerSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                Text("Want to connect another broker?")
                    .experienceStyle(.subheadline, color: colors.primaryText)
                    .fontWeight(.semibold)
                Text("You can connect another account now or add one anytime in Settings.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, ExperienceSpacing.xs)

            ForEach(unconnectedSupportedProviders, id: \.self) { provider in
                connectBrokerButton(provider)
            }
        }
    }

    private var brokerConnectOptionsSection: some View {
        VStack(spacing: ExperienceSpacing.sm) {
            if isProviderOfferedOnOnboarding(.tradovate) {
                connectBrokerButton(.tradovate)
                    .accessibilityIdentifier("onboarding.broker.tradovate")
            }
            if isProviderOfferedOnOnboarding(.rithmic) {
                connectBrokerButton(.rithmic)
                    .accessibilityIdentifier("onboarding.broker.rithmic")
            }
        }
    }

    private func connectBrokerButton(_ provider: BrokerIntegrationProvider) -> some View {
        Button {
            connect(provider)
        } label: {
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
        .disabled(isConnectDisabled(for: provider))
    }

    private func isConnectDisabled(for provider: BrokerIntegrationProvider) -> Bool {
        if viewModel.isBrokerConnectionMutationActive { return true }
        if provider == .rithmic, !viewModel.isRithmicConnectUIAvailable { return true }
        return false
    }

    private func connect(_ provider: BrokerIntegrationProvider) {
        switch provider {
        case .tradovate:
            viewModel.connectTradovate()
        case .rithmic:
            viewModel.presentRithmicConnect()
        }
    }

    private var linkingHint: some View {
        Text("Link your broker account to a TradeTraxs trading account to continue.")
            .experienceStyle(.footnote, color: colors.secondaryText)
    }

    private var continueButton: some View {
        ExperienceButton(
            title: "Continue to TradeTraxs",
            kind: .primary,
            isEnabled: true,
            isLoading: false,
            accessibilityIdentifier: "onboarding.broker.continue"
        ) {
            finishBrokerOnboarding()
        }
        .padding(.top, ExperienceSpacing.sm)
    }

    private var optionalConnectLaterHint: some View {
        (
            Text("Not ready to connect? You can connect or manage your trading platforms anytime in ")
            + Text("Settings → Manage Accounts").fontWeight(.semibold)
            + Text(".")
        )
        .experienceStyle(.footnote, color: colors.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, ExperienceSpacing.xs)
        .accessibilityIdentifier("onboarding.broker.optionalHint")
    }

    private var maybeLaterButton: some View {
        Button("Maybe Later") {
            finishBrokerOnboarding()
        }
        .font(ExperienceTypography.callout)
        .foregroundStyle(colors.accent)
        .frame(maxWidth: .infinity)
        .frame(minHeight: ExperienceAccessibility.minTouchTarget)
        .padding(.top, ExperienceSpacing.sm)
        .accessibilityIdentifier("onboarding.broker.skip")
    }

    private var nonOAuthActionMessage: String? {
        guard viewModel.actionIsError, let message = viewModel.actionMessage else { return nil }
        return message
    }

    private func finishBrokerOnboarding() {
        ExperienceHaptics.play(.selection)
        BrokerIntegrationMutationStore.shared.noteBrokerIntegrationChanged()
        BrokerImportEligibilityStore.shared.refresh(fromUserAction: false)
        gateStore.markBrokerOnboardingFinished()
    }

    private func promptLinkingIfNeeded() {
        guard linkTarget == nil, createLinkTarget == nil else { return }
        guard let next = viewModel.firstUnlinkedBrokerAccount() else { return }
        linkTarget = BrokerIntegrationLinkTarget(
            provider: next.provider,
            connectionId: next.connectionId,
            account: next.account
        )
    }
}
