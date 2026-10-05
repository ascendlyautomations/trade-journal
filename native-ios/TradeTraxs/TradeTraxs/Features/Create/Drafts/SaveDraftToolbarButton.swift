import SwiftUI

/// Small header action. Does not publish content.
struct SaveDraftToolbarButton: View {
    let isSaving: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isSaving {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text("Save Draft")
                    .font(.subheadline.weight(.regular))
            }
        }
        .disabled(!isEnabled || isSaving)
        .accessibilityIdentifier("composer.saveDraft")
    }
}
