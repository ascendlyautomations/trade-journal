import SwiftUI

/// Resolves broker eligibility at tap time, then shows broker import or trade-entry paths.
struct TradeImportReminderDestinationView: View {
    let data: DataEnvironment
    let navigation: NavigationCoordinator
    let onClose: () -> Void

    @State private var viewModel: TradeImportReminderDestinationViewModel
    @Environment(\.themeColors) private var colors

    init(data: DataEnvironment, navigation: NavigationCoordinator, onClose: @escaping () -> Void) {
        self.data = data
        self.navigation = navigation
        self.onClose = onClose
        _viewModel = State(
            initialValue: TradeImportReminderDestinationViewModel(
                session: data.session,
                eligibilityStore: BrokerImportEligibilityStore.shared
            )
        )
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .loading:
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ExperienceSpacing.xl)
            case .broker(let accounts):
                BrokerLinkedImportReminderView(
                    data: data,
                    accounts: accounts,
                    onClose: onClose
                )
            case .needsAccountLinking:
                brokerLinkingPrompt
            case .noBroker:
                tradeEntryFallback
            case .failed(let message):
                VStack(spacing: ExperienceSpacing.md) {
                    Text(message)
                        .experienceStyle(.body, color: colors.primaryText)
                    Button("Try Again") {
                        Task { await viewModel.resolve() }
                    }
                    Button("Close", action: onClose)
                }
                .padding(ExperienceSpacing.lg)
            }
        }
        .task {
            await viewModel.resolve()
        }
        .onChange(of: viewModel.shouldOpenTradeEntryHub) { _, shouldOpen in
            guard shouldOpen else { return }
            viewModel.shouldOpenTradeEntryHub = false
            onClose()
            TradeEntryLaunchIntent.prepare(hubTab: .csv)
            navigation.present(fullScreen: .addTrade)
        }
        .accessibilityIdentifier("tradeImportReminder.destination")
    }

    private var brokerLinkingPrompt: some View {
        List {
            Section {
                Text(
                    "Your broker is connected. Link a discovered broker account to a TradeTraxs trading account to import trades."
                )
                .experienceStyle(.footnote, color: colors.secondaryText)
            }
            Section {
                Button {
                    onClose()
                    navigation.open(.settingsStack([.home, .tradingAccounts, .brokerIntegrations]))
                } label: {
                    Label("Continue in Broker Integrations", systemImage: "link")
                }
            }
        }
        .listStyle(.insetGrouped)
        .experienceDashboardGroupedRows()
        .experienceNavigationTitle("Import Trades")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", action: onClose)
            }
        }
    }

    private var tradeEntryFallback: some View {
        List {
            Section {
                Text("Add or import trades, or connect a broker to sync from your platform.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }

            Section {
                Button {
                    viewModel.openTradeEntryHub()
                } label: {
                    Label("Add or Import Trades", systemImage: "square.and.arrow.down")
                }
                Button {
                    onClose()
                    navigation.open(.settingsStack([.home, .tradingAccounts, .brokerIntegrations]))
                } label: {
                    Label("Broker Integrations", systemImage: "link")
                }
            }
        }
        .listStyle(.insetGrouped)
        .experienceDashboardGroupedRows()
        .experienceNavigationTitle("Import Trades")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", action: onClose)
            }
        }
    }
}

@Observable
@MainActor
final class TradeImportReminderDestinationViewModel {
    enum Phase: Equatable {
        case loading
        case broker([BrokerImportEligibilityTarget])
        case needsAccountLinking
        case noBroker
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    var shouldOpenTradeEntryHub = false

    private let session: any SessionProviding
    private let eligibilityStore: BrokerImportEligibilityStore

    init(
        session: any SessionProviding,
        eligibilityStore: BrokerImportEligibilityStore
    ) {
        self.session = session
        self.eligibilityStore = eligibilityStore
        if eligibilityStore.isReady {
            applyCachedPhase(from: eligibilityStore)
        }
    }

    private func applyCachedPhase(from store: BrokerImportEligibilityStore) {
        if store.canImportImmediately, !store.linkedAccounts.isEmpty {
            phase = .broker(store.linkedAccounts)
        } else if store.needsAccountLinking || store.hasSupportedConnection {
            phase = .needsAccountLinking
        } else {
            phase = .noBroker
        }
    }

    func resolve() async {
        if case .broker = phase {
            // Show cached accounts immediately; refresh in background below.
        } else if case .needsAccountLinking = phase {
            // Keep linking prompt while refreshing.
        } else {
            phase = .loading
        }
        guard await session.currentUserID != nil else {
            phase = .failed("Sign in to import trades.")
            return
        }
        do {
            let eligibility = try await eligibilityStore.fetchEligibility()
            if eligibility.resolvedCanImportImmediately, !eligibility.linkedAccounts.isEmpty {
                phase = .broker(eligibility.linkedAccounts)
            } else if eligibility.resolvedNeedsAccountLinking {
                phase = .needsAccountLinking
            } else if eligibility.resolvedHasSupportedConnection {
                phase = .needsAccountLinking
            } else {
                phase = .noBroker
            }
        } catch {
            if case .broker = phase { return }
            if case .needsAccountLinking = phase { return }
            phase = .failed(UserFacingError.message(for: error))
        }
    }

    func openTradeEntryHub() {
        shouldOpenTradeEntryHub = true
    }
}
