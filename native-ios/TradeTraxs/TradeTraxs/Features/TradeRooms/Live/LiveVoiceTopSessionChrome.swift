import SwiftUI

/// Voice / stream chrome pinned under the navigation header (DM thread + Feed detail destinations).
private struct LiveVoiceTopSessionChromeInset: View {
    @Bindable private var broadcastCoordinator = RoomBroadcastCoordinator.shared
    @Bindable private var liveVoiceCoordinator = RoomLiveVoiceCoordinator.shared
    @Environment(\.themeColors) private var colors

    private var showsChrome: Bool {
        LiveVoiceTabShellLayout.needsBottomAccessory(
            showsDemoLeave: false,
            broadcastCoordinator: broadcastCoordinator,
            liveVoiceCoordinator: liveVoiceCoordinator
        )
    }

    var body: some View {
        Group {
            if showsChrome {
                LiveVoiceTabShellLayout.bottomAccessory(
                    showsDemoLeave: false,
                    broadcastCoordinator: broadcastCoordinator,
                    liveVoiceCoordinator: liveVoiceCoordinator
                )
                .background(colors.backgroundPrimary)
            }
        }
    }
}

private struct LiveVoiceTopSessionChromeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                LiveVoiceTopSessionChromeInset()
            }
            .onAppear {
                TradeRoomLiveSessionChromeMetrics.shared.setTopSessionChromeEmbedded(true)
            }
            .onDisappear {
                TradeRoomLiveSessionChromeMetrics.shared.setTopSessionChromeEmbedded(false)
            }
    }
}

extension View {
    /// Hosts voice chrome under the nav bar and suppresses the tab-shell bottom bar on this screen only.
    func liveVoiceTopSessionChrome() -> some View {
        modifier(LiveVoiceTopSessionChromeModifier())
    }
}