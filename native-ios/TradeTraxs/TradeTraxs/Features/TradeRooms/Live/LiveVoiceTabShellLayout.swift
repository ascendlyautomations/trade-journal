import SwiftUI

/// Shell-level placement for persistent Trade Room session chrome above the tab bar.
enum LiveVoiceTabShellLayout {
    @ViewBuilder
    static func bottomAccessory(
        showsDemoLeave: Bool,
        broadcastCoordinator: RoomBroadcastCoordinator,
        liveVoiceCoordinator: RoomLiveVoiceCoordinator
    ) -> some View {
        VStack(spacing: 0) {
            if broadcastCoordinator.showsBroadcastChrome {
                RoomBroadcastBar(coordinator: broadcastCoordinator)
            }
            if liveVoiceCoordinator.showsVoiceChrome {
                RoomLiveVoiceBar(coordinator: liveVoiceCoordinator)
            }
            if showsDemoLeave {
                DemoExperienceLeaveButtonPlacement()
            }
        }
    }

    static func needsBottomAccessory(
        showsDemoLeave: Bool,
        broadcastCoordinator: RoomBroadcastCoordinator,
        liveVoiceCoordinator: RoomLiveVoiceCoordinator
    ) -> Bool {
        showsDemoLeave
            || broadcastCoordinator.showsBroadcastChrome
            || liveVoiceCoordinator.showsVoiceChrome
    }
}

struct LiveVoiceTabShellLayoutModifier: ViewModifier {
    var showsDemoLeave: Bool
    @Bindable var broadcastCoordinator: RoomBroadcastCoordinator
    @Bindable var liveVoiceCoordinator: RoomLiveVoiceCoordinator

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if LiveVoiceTabShellLayout.needsBottomAccessory(
                showsDemoLeave: showsDemoLeave,
                broadcastCoordinator: broadcastCoordinator,
                liveVoiceCoordinator: liveVoiceCoordinator
            ) {
                LiveVoiceTabShellLayout.bottomAccessory(
                    showsDemoLeave: showsDemoLeave,
                    broadcastCoordinator: broadcastCoordinator,
                    liveVoiceCoordinator: liveVoiceCoordinator
                )
            }
        }
    }
}

extension View {
    func liveVoiceTabShellLayout(
        showsDemoLeave: Bool,
        broadcastCoordinator: RoomBroadcastCoordinator,
        liveVoiceCoordinator: RoomLiveVoiceCoordinator
    ) -> some View {
        modifier(
            LiveVoiceTabShellLayoutModifier(
                showsDemoLeave: showsDemoLeave,
                broadcastCoordinator: broadcastCoordinator,
                liveVoiceCoordinator: liveVoiceCoordinator
            )
        )
    }
}
