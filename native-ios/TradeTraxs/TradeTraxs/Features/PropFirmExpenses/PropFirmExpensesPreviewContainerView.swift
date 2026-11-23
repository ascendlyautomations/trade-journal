import SwiftUI

/// Full-screen TraxsPro Expense Tracker preview for signed-in Free users.
struct PropFirmExpensesPreviewContainerView: View {
    let data: DataEnvironment
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    init(data: DataEnvironment, onDismiss: @escaping () -> Void) {
        self.data = data
        self.onDismiss = onDismiss
        TraxsProPreviewSession.shared.beginExpenseTrackerPreview()
    }

    var body: some View {
        NavigationStack {
            PropFirmExpensesView(data: data, embeddedInTraxsProPreview: true)
                .safeAreaInset(edge: .top, spacing: 0) {
                    TraxsProPreviewSampleDataBanner(
                        unlockFeature: .propFirm,
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