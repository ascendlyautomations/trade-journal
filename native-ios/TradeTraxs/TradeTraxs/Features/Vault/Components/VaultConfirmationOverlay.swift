import SwiftUI

/// Subtle confirmation when content is saved to Vault.
struct VaultConfirmationOverlay: View {
    @Bindable var store: VaultStore

    @State private var visibleMessage: String?

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .overlay(alignment: .bottom) {
                if let visibleMessage {
                    ExperienceToast(message: visibleMessage, tone: .success)
                        .padding(.bottom, ExperienceSpacing.xl)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onChange(of: store.lastConfirmationMessage) { _, message in
                guard let message else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        visibleMessage = nil
                    }
                    return
                }
                withAnimation(.snappy(duration: 0.25)) {
                    visibleMessage = message
                }
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await MainActor.run {
                        if store.lastConfirmationMessage == message {
                            store.clearConfirmation()
                        }
                    }
                }
            }
    }
}

extension View {
    func vaultConfirmationOverlay(store: VaultStore) -> some View {
        overlay {
            VaultConfirmationOverlay(store: store)
        }
    }
}
