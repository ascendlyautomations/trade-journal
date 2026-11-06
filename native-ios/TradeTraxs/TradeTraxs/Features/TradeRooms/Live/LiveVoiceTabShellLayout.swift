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

// MARK: - iOS 26+ tab bar accessory (directly above tab bar, not over it)

@available(iOS 26.0, *)
struct LiveVoiceTabShellTabViewBottomAccessoryModifier: ViewModifier {
    var showsDemoLeave: Bool
    @Bindable var broadcastCoordinator: RoomBroadcastCoordinator
    @Bindable var liveVoiceCoordinator: RoomLiveVoiceCoordinator
    @Bindable private var chromeMetrics = TradeRoomLiveSessionChromeMetrics.shared

    func body(content: Content) -> some View {
        content
            .tabViewBottomAccessory {
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
                    .background(LiveVoiceTabAccessoryHeightReporter())
                }
            }
            .environment(\.tradeRoomLiveSessionBottomInset, chromeMetrics.bottomInset)
    }
}

@available(iOS 26.0, *)
private struct LiveVoiceTabAccessoryHeightReporter: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    TradeRoomLiveSessionChromeMetrics.shared.setBottomInset(proxy.size.height)
                }
                .onChange(of: proxy.size.height) { _, height in
                    TradeRoomLiveSessionChromeMetrics.shared.setBottomInset(height)
                }
        }
    }
}

// MARK: - iOS 18–25 UIKit bridge (tab bar top anchor + additionalSafeAreaInsets)

struct LiveVoiceTabShellLegacyTabBarAccessoryModifier: ViewModifier {
    var showsDemoLeave: Bool
    @Bindable var broadcastCoordinator: RoomBroadcastCoordinator
    @Bindable var liveVoiceCoordinator: RoomLiveVoiceCoordinator
    @Bindable private var chromeMetrics = TradeRoomLiveSessionChromeMetrics.shared

    func body(content: Content) -> some View {
        content
            .modifier(
                LiveVoiceTabBarAccessoryBridgeModifier {
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
                    } else {
                        Color.clear.frame(height: 0)
                    }
                }
            )
            .environment(\.tradeRoomLiveSessionBottomInset, chromeMetrics.bottomInset)
    }
}

extension View {
    func liveVoiceTabShellLayout(
        showsDemoLeave: Bool,
        broadcastCoordinator: RoomBroadcastCoordinator,
        liveVoiceCoordinator: RoomLiveVoiceCoordinator
    ) -> some View {
        modifier(
            LiveVoiceTabShellLegacyTabBarAccessoryModifier(
                showsDemoLeave: showsDemoLeave,
                broadcastCoordinator: broadcastCoordinator,
                liveVoiceCoordinator: liveVoiceCoordinator
            )
        )
    }

    @available(iOS 26.0, *)
    func liveVoiceTabShellLayoutIOS26(
        showsDemoLeave: Bool,
        broadcastCoordinator: RoomBroadcastCoordinator,
        liveVoiceCoordinator: RoomLiveVoiceCoordinator
    ) -> some View {
        modifier(
            LiveVoiceTabShellTabViewBottomAccessoryModifier(
                showsDemoLeave: showsDemoLeave,
                broadcastCoordinator: broadcastCoordinator,
                liveVoiceCoordinator: liveVoiceCoordinator
            )
        )
    }
}
