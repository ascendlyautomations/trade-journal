import SwiftUI

/// Published height of shell voice/stream chrome (above the tab bar).
@Observable
@MainActor
final class TradeRoomLiveSessionChromeMetrics {
    static let shared = TradeRoomLiveSessionChromeMetrics()

    private(set) var bottomInset: CGFloat = 0
    /// When true, ``RoomConversationView`` renders session chrome flush above the composer (tab shell skips its inset).
    private(set) var roomConversationEmbedsSessionChrome = false

    func setRoomConversationEmbedsSessionChrome(_ embeds: Bool) {
        guard roomConversationEmbedsSessionChrome != embeds else { return }
        roomConversationEmbedsSessionChrome = embeds
        if !embeds {
            setBottomInset(0)
        }
    }

    func setBottomInset(_ value: CGFloat) {
        let clamped = max(0, value)
        guard abs(bottomInset - clamped) > 0.5 else { return }
        bottomInset = clamped
    }
}

private struct TradeRoomLiveSessionBottomInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Extra space above the tab bar reserved for voice/stream session bars.
    var tradeRoomLiveSessionBottomInset: CGFloat {
        get { self[TradeRoomLiveSessionBottomInsetKey.self] }
        set { self[TradeRoomLiveSessionBottomInsetKey.self] = newValue }
    }
}

extension View {
    /// Room conversation embeds session chrome only while its tab is selected and the view is visible.
    func syncTradeRoomSessionChromeEmbedding(tabIsActive: Bool) -> some View {
        onAppear {
            TradeRoomLiveSessionChromeMetrics.shared.setRoomConversationEmbedsSessionChrome(tabIsActive)
        }
        .onDisappear {
            TradeRoomLiveSessionChromeMetrics.shared.setRoomConversationEmbedsSessionChrome(false)
        }
        .onChange(of: tabIsActive) { _, active in
            TradeRoomLiveSessionChromeMetrics.shared.setRoomConversationEmbedsSessionChrome(active)
        }
    }
}
