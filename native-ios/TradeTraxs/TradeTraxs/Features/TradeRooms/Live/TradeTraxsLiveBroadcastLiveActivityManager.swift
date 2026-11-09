import ActivityKit
import Foundation
import OSLog

@MainActor
final class TradeTraxsLiveBroadcastLiveActivityManager {
    static let shared = TradeTraxsLiveBroadcastLiveActivityManager()

    private var currentActivity: Activity<TradeTraxsLiveBroadcastActivityAttributes>?
    private var boundSessionEpoch: UInt64?

    private init() {}

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(
        tradeRoomName: String,
        roomID: String,
        sessionEpoch: UInt64,
        content: TradeTraxsLiveBroadcastActivityAttributes.ContentState
    ) {
        guard isSupported else { return }
        endAllImmediately()

        let attributes = TradeTraxsLiveBroadcastActivityAttributes(
            tradeRoomName: tradeRoomName,
            roomID: roomID,
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
            AppLog.application.info("Live Activity started for livestream epoch=\(sessionEpoch)")
        } catch {
            AppLog.application.error("Livestream Live Activity start failed: \(error.localizedDescription)")
        }
    }

    func update(sessionEpoch: UInt64, content: TradeTraxsLiveBroadcastActivityAttributes.ContentState) {
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
        content: TradeTraxsLiveBroadcastActivityAttributes.ContentState?,
        tradeRoomName: String?,
        roomID: String?
    ) {
        guard isSupported else { return }
        guard let sessionEpoch, let content, let tradeRoomName, let roomID else {
            endAllImmediately()
            return
        }
        if boundSessionEpoch == sessionEpoch, currentActivity != nil {
            update(sessionEpoch: sessionEpoch, content: content)
            return
        }
        start(
            tradeRoomName: tradeRoomName,
            roomID: roomID,
            sessionEpoch: sessionEpoch,
            content: content
        )
    }

    private func endAllImmediately() {
        for activity in Activity<TradeTraxsLiveBroadcastActivityAttributes>.activities {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        currentActivity = nil
        boundSessionEpoch = nil
    }
}
