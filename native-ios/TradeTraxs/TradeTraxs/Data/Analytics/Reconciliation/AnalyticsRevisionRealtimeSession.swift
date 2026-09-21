import Foundation

/// Session-scoped analytical revision Realtime watch — shared across Dashboard + Calendar.
@MainActor
final class AnalyticsRevisionRealtimeSession {
    static let shared = AnalyticsRevisionRealtimeSession()

    private var realtimeHub: RealtimeHub?
    private var session: (any SessionProviding)?
    private var coalescer = AnalyticsRevisionRealtimeCoalescer()
    private var watchTask: Task<Void, Never>?
    private var boundViewerID: ProfileID?
    private var boundGeneration: UInt64 = 0

    private init() {}

    func configure(realtimeHub: RealtimeHub?, session: any SessionProviding) {
        self.realtimeHub = realtimeHub
        self.session = session
    }

    func bindAuthenticatedViewer(_ viewerID: ProfileID) {
        guard AnalyticsRevisionRealtimeGate.isEnabled else { return }
        guard boundViewerID != viewerID else { return }
        stopWatch(reason: "viewer_switch")
        boundViewerID = viewerID
        boundGeneration &+= 1
        let generation = boundGeneration
        startWatch(viewerID: viewerID, generation: generation)
    }

    func invalidate() {
        stopWatch(reason: "logout")
        boundViewerID = nil
        boundGeneration &+= 1
        Task { await coalescer.reset() }
    }

    /// Called after Realtime socket reconnect + rejoin (6E may attach revision repair).
    func notifyReconnectIfBound() {
        guard let viewerID = boundViewerID else { return }
        AnalyticsReconciliationProbe.reconnect(viewer: viewerID.rawValue)
        Task {
            await AnalyticsRevisionRepairCoordinator.shared.requestRepair(.realtimeReconnect)
        }
    }

    private func startWatch(viewerID: ProfileID, generation: UInt64) {
        guard let realtimeHub else { return }
        let viewerRaw = viewerID.rawValue
        AnalyticsReconciliationProbe.subscribe(viewer: viewerRaw)
        watchTask = Task { [weak self] in
            guard let self else { return }
            let token = await self.session?.accessToken
            for await signal in realtimeHub.watchAnalyticsRevision(
                userID: viewerRaw,
                accessToken: token
            ) {
                guard !Task.isCancelled else { break }
                await self.handleSignal(signal, expectedViewer: viewerID, generation: generation)
            }
        }
    }

    private func stopWatch(reason: String) {
        watchTask?.cancel()
        watchTask = nil
        if let viewerID = boundViewerID?.rawValue {
            AnalyticsReconciliationProbe.unsubscribe(viewer: viewerID, reason: reason)
            Task { await realtimeHub?.stopWatchingAnalyticsRevision(userID: viewerID) }
        }
    }

    private func handleSignal(
        _ signal: MessageRealtimeSignal,
        expectedViewer: ProfileID,
        generation: UInt64
    ) async {
        guard generation == boundGeneration, boundViewerID == expectedViewer else { return }
        guard let session, await session.currentUserID?.rawValue == expectedViewer.rawValue else {
            return
        }

        guard signal.kind == .update else { return }
        let eventUserID = signal.conversationID ?? signal.messageID
        guard eventUserID == expectedViewer.rawValue else {
            #if DEBUG
            AnalyticsReconciliationProbe.coalesced(
                domain: "revision",
                revision: signal.analyticsRevision ?? -1,
                reason: "foreign_viewer"
            )
            #endif
            return
        }

        guard let revision = signal.analyticsRevision, revision > 0 else { return }

        await coalescer.ingest(revision: revision) { [weak self] maxRevision in
            guard let self else { return }
            let stillValid = await MainActor.run {
                generation == self.boundGeneration && self.boundViewerID == expectedViewer
            }
            guard stillValid else { return }
            await AnalyticsReconciliationCoordinator.shared.receive(
                .remoteRevision(serverRevision: maxRevision)
            )
        }
    }
}

/// Remote Realtime subscription — separate from local mutation coordinator gate.
nonisolated enum AnalyticsRevisionRealtimeGate {
    static var isEnabled: Bool {
        BackendV2FeatureFlags.isEnabled(.analyticsRealtime)
            && AnalyticsReconciliationGate.isEnabled
    }
}
