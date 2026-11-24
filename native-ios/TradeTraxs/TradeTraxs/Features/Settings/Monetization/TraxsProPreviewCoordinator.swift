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

    func dismissPreview(detailCache: DetailPresentationCache) {
        guard isPresented || TraxsProPreviewSession.shared.isAnyPreviewActive else {
            isPresented = false
            return
        }
        let feature = presentingFeature
            ?? TraxsProPreviewSession.shared.activeFeature
            ?? .reports
        let entryPoint = presentationEntryPoint ?? .previewBanner
        isPresented = false
        if TraxsProPreviewSession.shared.isReportsPreviewActive {
            TraxsProPreviewSession.shared.endReportsPreview(detailCache: detailCache)
        } else if TraxsProPreviewSession.shared.isDashboardPreviewActive {
            TraxsProPreviewSession.shared.endDashboardPreview(detailCache: detailCache)
        } else if TraxsProPreviewSession.shared.isExpenseTrackerPreviewActive {
            TraxsProPreviewSession.shared.endExpenseTrackerPreview()
        } else if TraxsProPreviewSession.shared.isTradingRulesPreviewActive {
            TraxsProPreviewSession.shared.endTradingRulesPreview(detailCache: detailCache)
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

    func body(content: Content) -> some View {
        content
            .fullScreenCover(
                isPresented: $previewCoordinator.isPresented,
                onDismiss: {
                    if TraxsProPreviewSession.shared.isAnyPreviewActive {
                        previewCoordinator.dismissPreview(detailCache: data.detailCache)
                    } else {
                        previewCoordinator.isPresented = false
                        previewCoordinator.resetPresentationStateKeepingSessionFlags()
                    }
                },
                content: {
                    TraxsProPreviewCoverContent(data: data) {
                        previewCoordinator.dismissPreview(detailCache: data.detailCache)
                    }
                }
            )
    }
}

private struct TraxsProPreviewCoverContent: View {
  let data: DataEnvironment
    let onDismiss: () -> Void

    @Bindable private var previewCoordinator = TraxsProPreviewCoordinator.shared

    var body: some View {
        Group {
            switch previewCoordinator.presentingFeature ?? .reports {
            case .reports:
                ReportsPreviewContainerView(data: data, onDismiss: onDismiss)
            case .dashboard:
                DashboardPreviewContainerView(data: data, onDismiss: onDismiss)
            case .expenseTracker:
                PropFirmExpensesPreviewContainerView(data: data, onDismiss: onDismiss)
            case .tradingRules:
                TradingRulesPreviewContainerView(data: data, onDismiss: onDismiss)
            }
        }
    }
}

extension View {
    @MainActor
    func traxsProPreviewCover(data: DataEnvironment) -> some View {
        modifier(TraxsProPreviewCoverModifier(data: data))
    }

    @MainActor
    func traxsProReportsPreviewCover(data: DataEnvironment) -> some View {
        traxsProPreviewCover(data: data)
    }
}