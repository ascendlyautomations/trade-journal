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

/// Voice/stream bar is a bottom `safeAreaInset` so it sits flush on the tab bar or message composer (no floating gap).
struct LiveVoiceTabShellLayoutModifier: ViewModifier {
    var showsDemoLeave: Bool
    @Bindable var broadcastCoordinator: RoomBroadcastCoordinator
    @Bindable var liveVoiceCoordinator: RoomLiveVoiceCoordinator
    @Bindable private var sessionMetrics = TradeRoomLiveSessionChromeMetrics.shared
    @Bindable private var tabBarMetrics = MainTabBarLayoutMetrics.shared

    private var showsChrome: Bool {
        LiveVoiceTabShellLayout.needsBottomAccessory(
            showsDemoLeave: showsDemoLeave,
            broadcastCoordinator: broadcastCoordinator,
            liveVoiceCoordinator: liveVoiceCoordinator
        )
    }

    /// Tab-level inset only when the tab bar is visible; in-room chrome is stacked on the composer instead.
    private var showsTabShellChrome: Bool {
        showsChrome && !sessionMetrics.roomConversationEmbedsSessionChrome
    }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                sessionChromeInset
            }
            .background {
                MainTabBarLayoutMetricsProbe()
            }
            .environment(\.tradeRoomLiveSessionBottomInset, sessionMetrics.bottomInset)
            .onChange(of: showsChrome) { _, _ in
                syncSessionChromeInsetEstimate()
                tabBarMetrics.refresh()
            }
            .onChange(of: sessionMetrics.roomConversationEmbedsSessionChrome) { _, _ in
                syncSessionChromeInsetEstimate()
                tabBarMetrics.refresh()
            }
            .onAppear {
                syncSessionChromeInsetEstimate()
                tabBarMetrics.refresh()
            }
    }

    /// Chrome sits directly above the tab bar (spacer = window bottom → tab bar top), not on the home indicator.
    @ViewBuilder
    private var sessionChromeInset: some View {
        if showsTabShellChrome {
            VStack(spacing: 0) {
                tabShellSessionChrome
                Color.clear
                    .frame(height: tabBarMetrics.tabBarTopInsetFromBottom)
                    .accessibilityHidden(true)
            }
        }
    }

    private var tabShellSessionChrome: some View {
        LiveVoiceTabShellLayout.bottomAccessory(
            showsDemoLeave: showsDemoLeave,
            broadcastCoordinator: broadcastCoordinator,
            liveVoiceCoordinator: liveVoiceCoordinator
        )
        .background {
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

    private func syncSessionChromeInsetEstimate() {
        if !showsTabShellChrome {
            TradeRoomLiveSessionChromeMetrics.shared.setBottomInset(0)
        }
    }
}

/// Session chrome pinned directly above the room message composer (no gap vs tab-bar inset).
struct RoomConversationSessionChrome: View {
    @Bindable private var sessionMetrics = TradeRoomLiveSessionChromeMetrics.shared
    @Bindable var broadcastCoordinator: RoomBroadcastCoordinator
    @Bindable var liveVoiceCoordinator: RoomLiveVoiceCoordinator

    private var showsChrome: Bool {
        broadcastCoordinator.showsBroadcastChrome || liveVoiceCoordinator.showsVoiceChrome
    }

    var body: some View {
        Group {
            if showsChrome {
                LiveVoiceTabShellLayout.bottomAccessory(
                    showsDemoLeave: false,
                    broadcastCoordinator: broadcastCoordinator,
                    liveVoiceCoordinator: liveVoiceCoordinator
                )
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear {
                                sessionMetrics.setBottomInset(proxy.size.height)
                            }
                            .onChange(of: proxy.size.height) { _, height in
                                sessionMetrics.setBottomInset(height)
                            }
                    }
                }
            }
        }
        .onAppear {
            sessionMetrics.setRoomConversationEmbedsSessionChrome(true)
        }
        .onDisappear {
            sessionMetrics.setRoomConversationEmbedsSessionChrome(false)
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
