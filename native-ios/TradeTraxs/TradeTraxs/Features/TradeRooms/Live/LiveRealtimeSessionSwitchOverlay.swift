import SwiftUI

struct LiveRealtimeSessionSwitchOverlay: ViewModifier {
    @Bindable private var gate = LiveRealtimeSessionSwitchGate.shared

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                gate.prompt?.title ?? "Leave Current Call?",
                isPresented: Binding(
                    get: { gate.showsPrompt },
                    set: { isPresented in
                        if !isPresented {
                            gate.cancelPendingSwitch()
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                Button("Leave & Join", role: .destructive) {
                    gate.confirmLeaveAndJoin()
                }
                Button("Cancel", role: .cancel) {
                    gate.cancelPendingSwitch()
                }
            } message: {
                Text(gate.prompt?.message ?? "")
            }
    }
}

extension View {
    func liveRealtimeSessionSwitchOverlay() -> some View {
        modifier(LiveRealtimeSessionSwitchOverlay())
    }
}