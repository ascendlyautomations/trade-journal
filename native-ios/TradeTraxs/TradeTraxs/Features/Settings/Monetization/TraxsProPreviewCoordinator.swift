import SwiftUI

/// Presents TraxsPro interactive previews without altering auth, Explore, or global Pro entitlements.
@Observable
@MainActor
final class TraxsProPreviewCoordinator {
    static let shared = TraxsProPreviewCoordinator()

    var isPresented = false
    private(set) var presentationEntryPoint: TraxsProPreviewEntryPoint?
    private(set) var presentingFeature: TraxsProPreviewFeature?
    private var scheduledFeature: TraxsProPreviewFeature?
    private var scheduledEntryPoint: TraxsProPreviewEntryPoint?

    private init() {}

    var canPresentPreview: Bool {
        !ExploreModeSupport.isActive
            && !TraxsProPreviewSession.shared.isAnyPreviewActive
            && !isPresented
    }

    func presentReportsPreview(entryPoint: TraxsProPreviewEntryPoint) {
        presentPreview(feature: .reports, entryPoint: entryPoint)
    }

    func presentDashboardPreview(entryPoint: TraxsProPreviewEntryPoint) {
        presentPreview(feature: .dashboard, entryPoint: entryPoint)
    }

    func presentExpenseTrackerPreview(entryPoint: TraxsProPreviewEntryPoint) {
        presentPreview(feature: .expenseTracker, entryPoint: entryPoint)
    }

    func presentTradingRulesPreview(entryPoint: TraxsProPreviewEntryPoint) {
        presentPreview(feature: .tradingRules, entryPoint: entryPoint)
    }

    func presentBacktestLabPreview(entryPoint: TraxsProPreviewEntryPoint) {
        presentPreview(feature: .backtestLab, entryPoint: entryPoint)
    }

    func presentPreview(feature: TraxsProPreviewFeature, entryPoint: TraxsProPreviewEntryPoint) {
        guard canPresentPreview else { return }
        presentationEntryPoint = entryPoint
        presentingFeature = feature
        isPresented = true
        ProductAnalyticsCoordinator.shared.noteTraxsProPreviewStarted(
            entryPoint: entryPoint,
            previewFeature: feature
        )
    }

    func scheduleReportsPreviewAfterPaywallDismiss(entryPoint: TraxsProPreviewEntryPoint) {
        schedulePreviewAfterPaywallDismiss(feature: .reports, entryPoint: entryPoint)
    }

    func scheduleDashboardPreviewAfterPaywallDismiss(entryPoint: TraxsProPreviewEntryPoint) {
        schedulePreviewAfterPaywallDismiss(feature: .dashboard, entryPoint: entryPoint)
    }

    func scheduleExpenseTrackerPreviewAfterPaywallDismiss(entryPoint: TraxsProPreviewEntryPoint) {
        schedulePreviewAfterPaywallDismiss(feature: .expenseTracker, entryPoint: entryPoint)
    }

    /// Dismisses the paywall first, then presents on the next sheet transition.
    func schedulePreviewAfterPaywallDismiss(
        feature: TraxsProPreviewFeature,
        entryPoint: TraxsProPreviewEntryPoint
    ) {
        guard canPresentPreview else { return }
        scheduledFeature = feature
        scheduledEntryPoint = entryPoint
        if ProUpgradeCoordinator.shared.isPresented {
            ProUpgradeCoordinator.shared.dismiss()
        } else {
            consumeScheduledPresentation()
        }
    }

    func paywallDidDismiss() {
        consumeScheduledPresentation()
    }

    private func consumeScheduledPresentation() {
        guard let feature = scheduledFeature, let entryPoint = scheduledEntryPoint else { return }
        scheduledFeature = nil
        scheduledEntryPoint = nil
        presentPreview(feature: feature, entryPoint: entryPoint)
    }

    func dismissPreview(
        productionData: DataEnvironment,
        navigationCoordinator: NavigationCoordinator? = nil
    ) {
        guard isPresented || TraxsProPreviewSession.shared.isAnyPreviewActive else {
            isPresented = false
            return
        }
        let feature = presentingFeature
            ?? TraxsProPreviewSession.shared.activeFeature
            ?? .reports
        let entryPoint = presentationEntryPoint ?? .previewBanner
        let viewer = SessionBootstrapStore.shared.last.map { ProfileID($0.data.viewer.id) }
        isPresented = false
        TraxsProPreviewSession.shared.endActivePreview()
        navigationCoordinator?.restoreTradingRulesSettingsAfterPreview(entryPoint: entryPoint)
        if let viewer {
            TraxsProProductionRecovery.recoverAfterPreview(
                production: productionData,
                viewer: viewer
            )
        }
        ProductAnalyticsCoordinator.shared.noteTraxsProPreviewExited(
            entryPoint: entryPoint,
            previewFeature: feature
        )
        presentationEntryPoint = nil
        presentingFeature = nil
    }

    func noteUpgradeTappedFromPreviewBanner() {
        let feature = presentingFeature
            ?? TraxsProPreviewSession.shared.activeFeature
            ?? .reports
        let entryPoint = presentationEntryPoint ?? .previewBanner
        ProductAnalyticsCoordinator.shared.noteTraxsProPreviewUpgradeTapped(
            entryPoint: entryPoint,
            previewFeature: feature
        )
    }

    func resetPresentationStateKeepingSessionFlags() {
        presentationEntryPoint = nil
        presentingFeature = nil
        scheduledFeature = nil
        scheduledEntryPoint = nil
    }

    func resetForTesting() {
        isPresented = false
        presentationEntryPoint = nil
        presentingFeature = nil
        scheduledFeature = nil
        scheduledEntryPoint = nil
    }
}

struct TraxsProPreviewCoverModifier: ViewModifier {
    @Bindable private var previewCoordinator = TraxsProPreviewCoordinator.shared
    let data: DataEnvironment
    let navigationCoordinator: NavigationCoordinator

    func body(content: Content) -> some View {
        content
            .fullScreenCover(
                isPresented: $previewCoordinator.isPresented,
                onDismiss: {
                    if TraxsProPreviewSession.shared.isAnyPreviewActive {
                        previewCoordinator.dismissPreview(
                            productionData: data,
                            navigationCoordinator: navigationCoordinator
                        )
                    } else {
                        previewCoordinator.isPresented = false
                        previewCoordinator.resetPresentationStateKeepingSessionFlags()
                    }
                },
                content: {
                    TraxsProPreviewCoverContent(productionData: data) {
                        previewCoordinator.dismissPreview(
                            productionData: data,
                            navigationCoordinator: navigationCoordinator
                        )
                    }
                }
            )
    }
}

private struct TraxsProPreviewCoverContent: View {
    let productionData: DataEnvironment
    let onDismiss: () -> Void

    @Bindable private var previewCoordinator = TraxsProPreviewCoordinator.shared

    var body: some View {
        Group {
            switch previewCoordinator.presentingFeature ?? .reports {
            case .reports:
                ReportsPreviewContainerView(productionData: productionData, onDismiss: onDismiss)
            case .dashboard:
                DashboardPreviewContainerView(productionData: productionData, onDismiss: onDismiss)
            case .expenseTracker:
                PropFirmExpensesPreviewContainerView(productionData: productionData, onDismiss: onDismiss)
            case .tradingRules:
                TradingRulesPreviewContainerView(productionData: productionData, onDismiss: onDismiss)
            case .backtestLab:
                BacktestLabPreviewContainerView(productionData: productionData, onDismiss: onDismiss)
            }
        }
    }
}

extension View {
    @MainActor
    func traxsProPreviewCover(data: DataEnvironment, navigationCoordinator: NavigationCoordinator) -> some View {
        modifier(TraxsProPreviewCoverModifier(data: data, navigationCoordinator: navigationCoordinator))
    }

    @MainActor
    func traxsProReportsPreviewCover(data: DataEnvironment, navigationCoordinator: NavigationCoordinator) -> some View {
        traxsProPreviewCover(data: data, navigationCoordinator: navigationCoordinator)
    }
}