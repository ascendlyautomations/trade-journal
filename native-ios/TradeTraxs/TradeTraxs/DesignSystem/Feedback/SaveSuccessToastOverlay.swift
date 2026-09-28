import SwiftUI

/// Non-blocking success toast for explicit save confirmations (Settings / Profile).
struct SaveSuccessToastOverlay: View {
    @Bindable private var center = SaveSuccessConfirmationCenter.shared

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
            .onChange(of: center.message) { _, message in
                guard let message else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        visibleMessage = nil
                    }
                    return
                }
                withAnimation(.snappy(duration: 0.25)) {
                    visibleMessage = message
                }
            }
    }
}

extension View {
    func saveSuccessToastOverlay() -> some View {
        overlay {
            SaveSuccessToastOverlay()
        }
    }
}
