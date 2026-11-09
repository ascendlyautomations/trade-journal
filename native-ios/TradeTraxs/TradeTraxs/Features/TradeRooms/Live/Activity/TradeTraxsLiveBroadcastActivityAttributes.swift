import ActivityKit
import Foundation

/// ActivityKit attributes for livestream viewing (main app + widget extension copies must match).
public struct TradeTraxsLiveBroadcastActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var connectionLabel: String
        public var viewerCount: Int
        public var isLive: Bool

        public init(connectionLabel: String, viewerCount: Int, isLive: Bool) {
            self.connectionLabel = connectionLabel
            self.viewerCount = viewerCount
            self.isLive = isLive
        }
    }

    public var tradeRoomName: String
    public var roomID: String
    public var sessionEpoch: UInt64

    public init(tradeRoomName: String, roomID: String, sessionEpoch: UInt64) {
        self.tradeRoomName = tradeRoomName
        self.roomID = roomID
        self.sessionEpoch = sessionEpoch
    }
}
