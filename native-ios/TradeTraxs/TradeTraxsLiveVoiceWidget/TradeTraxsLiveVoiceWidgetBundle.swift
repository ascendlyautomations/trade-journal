import SwiftUI
import WidgetKit

@main
struct TradeTraxsLiveVoiceWidgetBundle: WidgetBundle {
    var body: some Widget {
        TradeTraxsLiveVoiceLiveActivityWidget()
        TradeTraxsLiveBroadcastLiveActivityWidget()
    }
}
