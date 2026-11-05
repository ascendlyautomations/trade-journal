import Foundation

extension Notification.Name {
    /// Posted when a Trade Room live voice session connects — feed / voice notes should yield.
    static let tradeTraxsLiveVoiceSessionDidChange =
        Notification.Name("tradetraxs.liveVoiceSessionDidChange")
}
