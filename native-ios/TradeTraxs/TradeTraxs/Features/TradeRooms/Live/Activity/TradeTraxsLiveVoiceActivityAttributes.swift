import ActivityKit
import Foundation

/// ActivityKit attributes for General Voice (main app + widget extension copies must match).
public struct TradeTraxsLiveVoiceActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var connectionLabel: String
        public var participantCount: Int
        public var isMicrophoneEnabled: Bool
        public var isHandRaised: Bool
        public var raisedHandCount: Int

        public init(
            connectionLabel: String,
            participantCount: Int,
            isMicrophoneEnabled: Bool,
            isHandRaised: Bool,
            raisedHandCount: Int
        ) {
            self.connectionLabel = connectionLabel
            self.participantCount = participantCount
            self.isMicrophoneEnabled = isMicrophoneEnabled
            self.isHandRaised = isHandRaised
            self.raisedHandCount = raisedHandCount
        }
    }

    public var tradeRoomName: String
    public var channelName: String
    public var sessionEpoch: UInt64

    public init(tradeRoomName: String, channelName: String, sessionEpoch: UInt64) {
        self.tradeRoomName = tradeRoomName
        self.channelName = channelName
        self.sessionEpoch = sessionEpoch
    }
}

public enum TradeTraxsLiveVoiceActivityConstants {
    public static let handSignalTopic = "tt_general_voice_hand"
}
