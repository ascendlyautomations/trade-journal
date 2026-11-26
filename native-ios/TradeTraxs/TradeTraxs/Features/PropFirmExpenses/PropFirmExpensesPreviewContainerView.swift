import SwiftUI

/// Full-screen TraxsPro Expense Tracker preview for signed-in Free users.
struct PropFirmExpensesPreviewContainerView: View {
    let productionData: DataEnvironment
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var previewData: DataEnvironment {
        TraxsProPreviewSession.shared.activePreviewEnvironment?.data ?? productionData
    }

    init(productionData: DataEnvironment, onDismiss: @escaping () -> Void) {
        self.productionData = productionData
        self.onDismiss = onDismiss
        if let viewer = SessionBootstrapStore.shared.last.map({ ProfileID($0.data.viewer.id) }) {
            TraxsProPreviewSession.shared.beginExpenseTrackerPreview(
                production: productionData,
                viewer: viewer
            )
        }
    }

    var body: some View {
        NavigationStack {
            PropFirmExpensesView(data: previewData, embeddedInTraxsProPreview: true)
                .safeAreaInset(edge: .top, spacing: 0) {
                    TraxsProSampleDataHeader(
                        unlockFeature: .propFirm,
                        subtitle: MonetizationPlanCopy.expenseTrackerPreviewSampleDataSubtitle,
                        onExit: exitPreview,
                        onUnlock: {
                            ExperienceHaptics.play(.selection)
                            TraxsProPreviewCoordinator.shared.noteUpgradeTappedFromPreviewBanner()
                            ProUpgradeCoordinator.shared.present(reason: .feature(.propFirm))
                        }
                    )
                }
        }
        .environment(\.traxsProPreviewReadOnly, true)
        .accessibilityIdentifier("traxspro.preview.expenseTracker.container")
    }

    private func exitPreview() {
        ExperienceHaptics.play(.selection)
        onDismiss()
        dismiss()
    }
}