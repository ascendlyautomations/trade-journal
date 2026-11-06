import ActivityKit
import Foundation
import OSLog

@MainActor
final class TradeTraxsLiveVoiceLiveActivityManager {
    static let shared = TradeTraxsLiveVoiceLiveActivityManager()

    private var currentActivity: Activity<TradeTraxsLiveVoiceActivityAttributes>?
    private var boundSessionEpoch: UInt64?

    private init() {}

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(
        tradeRoomName: String,
        channelName: String,
        sessionEpoch: UInt64,
        content: TradeTraxsLiveVoiceActivityAttributes.ContentState
    ) {
        guard isSupported else { return }
        endAllImmediately()

        let attributes = TradeTraxsLiveVoiceActivityAttributes(
            tradeRoomName: tradeRoomName,
            channelName: channelName,
            sessionEpoch: sessionEpoch
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: content, staleDate: nil),
                pushType: nil
            )
            currentActivity = activity
            boundSessionEpoch = sessionEpoch
            AppLog.application.info("Live Activity started for General Voice epoch=\(sessionEpoch)")
        } catch {
            AppLog.application.error("Live Activity start failed: \(error.localizedDescription)")
        }
    }

    func update(
        sessionEpoch: UInt64,
        content: TradeTraxsLiveVoiceActivityAttributes.ContentState
    ) {
        guard isSupported else { return }
        guard boundSessionEpoch == sessionEpoch, let activity = currentActivity else { return }
        Task {
            await activity.update(.init(state: content, staleDate: nil))
        }
    }

    func end(sessionEpoch: UInt64?) {
        guard isSupported else { return }
        if let sessionEpoch, boundSessionEpoch != sessionEpoch { return }
        endAllImmediately()
    }

    func reconcileAfterForeground(
        sessionEpoch: UInt64?,
        content: TradeTraxsLiveVoiceActivityAttributes.ContentState?,
        tradeRoomName: String?,
        channelName: String?
    ) {
        guard isSupported else { return }
        guard let sessionEpoch, let content, let tradeRoomName, let channelName else {
            endAllImmediately()
            return
        }
        if boundSessionEpoch == sessionEpoch, currentActivity != nil {
            update(sessionEpoch: sessionEpoch, content: content)
            return
        }
        start(
            tradeRoomName: tradeRoomName,
            channelName: channelName,
            sessionEpoch: sessionEpoch,
            content: content
        )
    }

    private func endAllImmediately() {
        let activities = Activity<TradeTraxsLiveVoiceActivityAttributes>.activities
        for activity in activities {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        currentActivity = nil
        boundSessionEpoch = nil
    }
}
