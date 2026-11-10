import LiveKit
import Observation
import SwiftUI
import UIKit

/// Owner-only OBS broadcast control — BFF + LiveKit preview subscribe only (no iOS camera/mic capture).
@Observable
@MainActor
final class TradeRoomObsBroadcastController {
    static let shared = TradeRoomObsBroadcastController()

    enum Phase: Equatable {
        case idle
        case preparing
        case livePublic
    }

    private let broadcastCoordinator = RoomBroadcastCoordinator.shared

    private var client: LiveKitBroadcastClient?
    private var obsPollTask: Task<Void, Never>?

    /// Supabase auth user id (matches `broadcasterUserId` on broadcast rows).
    private(set) var viewerUserId: String?

    private(set) var phase: Phase = .idle
    private(set) var errorMessage: String?
    private(set) var isBusy = false
    /// True while `ensurePrivateObsSession` is running (status → start → credentials → preview).
    private(set) var isEnsuringPrivateObsSession = false

    private(set) var broadcastSessionId: String?
    private(set) var broadcasterUserId: String?
    private(set) var rtmpURL: String?
    /// In memory only — never persisted.
    private(set) var streamKey: String?
    var streamKeyRevealed = false

    private(set) var ingressStatusLabel: String?
    private(set) var encoderConnected = false
    private(set) var hostLiveKitConnected = false

    private(set) var publicDiscoverableLive = false
    private(set) var visibility: String?
    /// Server reports an OBS prep session owned by another user — do not call `startBroadcast`.
    private(set) var foreignHostPreparing = false
    private var serverIngressId: String?

    private(set) var hostContextRoomID: RoomID?
    private(set) var hostContextRoomTitle: String?

    /// Unstructured task so SwiftUI `.task` cancellation does not tear down in-flight setup.
    private var ensurePrivateObsSessionTask: Task<Void, Never>?
    private var ensurePrivateObsSessionRoomID: RoomID?
    private var ensurePrivateObsSessionGeneration: UInt64 = 0
    private var cachedObsHostStartResponse: LiveKitBroadcastStartResponse?
    private var cachedObsHostStartSessionId: String?
    private var obsCredentialsFlightSessionId: String?
    private var obsCredentialsFlight: Task<Void, Never>?

    func configure(viewerUserId: String?, transport: SupabaseTransport?) {
        self.viewerUserId = viewerUserId
        if let transport {
            client = LiveKitBroadcastClient(transport: transport)
        } else {
            client = nil
        }
    }

    /// Sheet closed without ending the broadcast — keep session phase for Manage Stream reopen.
    func acknowledgeManagementSheetDismissed() {
        obsPollTask?.cancel()
        obsPollTask = nil
        errorMessage = nil
        if phase == .livePublic {
            streamKey = nil
            streamKeyRevealed = false
            rtmpURL = nil
        }
    }

    func resetForDismiss() {
        cancelInFlightPrivateObsSessionEnsure()
        obsPollTask?.cancel()
        obsPollTask = nil
        streamKey = nil
        streamKeyRevealed = false
        phase = .idle
        errorMessage = nil
        ingressStatusLabel = nil
        encoderConnected = false
        hostLiveKitConnected = false
        broadcastSessionId = nil
        broadcasterUserId = nil
        publicDiscoverableLive = false
        visibility = nil
        foreignHostPreparing = false
        serverIngressId = nil
        cachedObsHostStartResponse = nil
        cachedObsHostStartSessionId = nil
        obsCredentialsFlight?.cancel()
        obsCredentialsFlight = nil
        obsCredentialsFlightSessionId = nil
        syncObsHostBarSession()
        Task { await broadcastCoordinator.disconnectObsHostPreview() }
    }

    func noteHostContext(roomID: RoomID, roomTitle: String?) {
        hostContextRoomID = roomID
        if let roomTitle, !roomTitle.isEmpty {
            hostContextRoomTitle = roomTitle
        }
    }

    private func syncObsHostBarSession() {
        guard phase == .livePublic,
              let sessionId = broadcastSessionId,
              !sessionId.isEmpty,
              let roomID = hostContextRoomID
        else {
            broadcastCoordinator.clearObsHostBarSession()
            return
        }
        let title = hostContextRoomTitle ?? "Trade Room"
        broadcastCoordinator.setObsHostBarSession(roomID: roomID, roomTitle: title)
    }

    /// Reconcile room state from server (existing preparing/public session, or idle).
    func refreshFromServer(roomID: RoomID) async {
        noteHostContext(roomID: roomID, roomTitle: hostContextRoomTitle)
        if isEnsuringPrivateObsSession, hostContextRoomID == roomID {
            return
        }
        guard let client else {
            errorMessage = "Sign in to manage streams."
            return
        }
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            let status = try await client.fetchStatus(roomID: roomID, reconcile: true, lite: false)
            await applyStatus(status, roomID: roomID)
        } catch {
            errorMessage = obsUserFacingError(error)
        }
    }

    /// Kicks off OBS private prep unless an ensure is already running for this room.
    func startPrivateObsSessionEnsureIfNeeded(roomID: RoomID) {
        noteHostContext(roomID: roomID, roomTitle: hostContextRoomTitle)

        if let ensurePrivateObsSessionTask,
           ensurePrivateObsSessionRoomID == roomID,
           !ensurePrivateObsSessionTask.isCancelled
        {
            return
        }

        if ensurePrivateObsSessionRoomID == roomID,
           phase == .preparing,
           let sessionId = broadcastSessionId,
           !sessionId.isEmpty,
           broadcasterUserId == viewerUserId,
           !foreignHostPreparing,
           broadcastCoordinator.obsHostPreviewConnectionState == .connected,
           rtmpURL != nil,
           streamKey != nil
        {
            startObsPolling(roomID: roomID, sessionId: sessionId)
            return
        }

        if let ensurePrivateObsSessionRoomID,
           ensurePrivateObsSessionRoomID != roomID,
           let ensurePrivateObsSessionTask,
           !ensurePrivateObsSessionTask.isCancelled
        {
            cancelInFlightPrivateObsSessionEnsure()
        }

        ensurePrivateObsSessionRoomID = roomID
        ensurePrivateObsSessionGeneration &+= 1
        let generation = ensurePrivateObsSessionGeneration
        let task = Task { @MainActor in
            await self.runPrivateObsSessionEnsure(roomID: roomID, generation: generation)
        }
        ensurePrivateObsSessionTask = task
    }

    /// Waits for in-flight ensure started by ``startPrivateObsSessionEnsureIfNeeded`` (safe across sheet transitions).
    func ensurePrivateObsSession(roomID: RoomID) async {
        startPrivateObsSessionEnsureIfNeeded(roomID: roomID)
        await ensurePrivateObsSessionTask?.value
    }

    private func cancelInFlightPrivateObsSessionEnsure() {
        ensurePrivateObsSessionTask?.cancel()
        ensurePrivateObsSessionTask = nil
        ensurePrivateObsSessionRoomID = nil
        ensurePrivateObsSessionGeneration &+= 1
    }

    private func shouldPreserveObsHostPreviewDuringStatusReconcile(roomID: RoomID) -> Bool {
        if isEnsuringPrivateObsSession, hostContextRoomID == roomID { return true }
        if phase == .preparing,
           hostContextRoomID == roomID,
           broadcastSessionId != nil
        {
            return true
        }
        return false
    }

    private func disconnectObsHostPreviewUnlessPreserving(roomID: RoomID) async {
        guard !shouldPreserveObsHostPreviewDuringStatusReconcile(roomID: roomID) else { return }
        await broadcastCoordinator.disconnectObsHostPreview()
    }

    private func cachedStartResponse(for sessionId: String) -> LiveKitBroadcastStartResponse? {
        guard cachedObsHostStartSessionId == sessionId else { return nil }
        return cachedObsHostStartResponse
    }

    private func rememberObsHostStartResponse(_ start: LiveKitBroadcastStartResponse, sessionId: String) {
        cachedObsHostStartResponse = start
        cachedObsHostStartSessionId = sessionId
    }

    private func hostStartResponse(
        roomID: RoomID,
        client: LiveKitBroadcastClient,
        sessionId: String
    ) async throws -> LiveKitBroadcastStartResponse {
        if isEnsuringPrivateObsSession, let cached = cachedStartResponse(for: sessionId) {
            return cached
        }
        let start = try await client.startBroadcast(
            roomID: roomID,
            voiceMode: "broadcast_only",
            videoSource: "obs"
        )
        rememberObsHostStartResponse(start, sessionId: sessionId)
        return start
    }

    private func runPrivateObsSessionEnsure(roomID: RoomID, generation: UInt64) async {
        defer {
            if generation == ensurePrivateObsSessionGeneration {
                ensurePrivateObsSessionTask = nil
                isBusy = false
                isEnsuringPrivateObsSession = false
            }
        }

        guard !Task.isCancelled, generation == ensurePrivateObsSessionGeneration else { return }

        guard let client else {
            errorMessage = "Sign in to manage streams."
            return
        }
        guard let viewerUserId, !viewerUserId.isEmpty else {
            errorMessage = "Sign in to manage streams."
            return
        }

        errorMessage = nil
        isBusy = true
        isEnsuringPrivateObsSession = true

        do {
            #if DEBUG
            TradeRoomObsBroadcastDiagnostics.log("ensure.status", roomID: roomID)
            #endif
            let status = try await client.fetchStatus(roomID: roomID, reconcile: true, lite: false)
            await applyStatus(status, roomID: roomID)

            if phase == .livePublic {
                if let sid = broadcastSessionId {
                    startObsPolling(roomID: roomID, sessionId: sid)
                }
                syncObsHostBarSession()
                return
            }

            if foreignHostPreparing {
                return
            }

            if phase == .preparing,
               let sid = broadcastSessionId,
               broadcasterUserId == viewerUserId
            {
                if rtmpURL == nil || streamKey == nil {
                    await loadCredentialsIfNeeded(
                        roomID: roomID,
                        sessionId: sid,
                        status: status
                    )
                }
                if broadcastCoordinator.obsHostPreviewConnectionState == .disconnected {
                    #if DEBUG
                    TradeRoomObsBroadcastDiagnostics.log("ensure.previewToken", roomID: roomID, sessionId: sid)
                    #endif
                    let start = try await hostStartResponse(
                        roomID: roomID,
                        client: client,
                        sessionId: sid
                    )
                    let programId =
                        start.primaryMediaPublisherIdentity?.trimmingCharacters(in: .whitespacesAndNewlines)
                        ?? status.primaryMediaPublisherIdentity?.trimmingCharacters(in: .whitespacesAndNewlines)
                    try await broadcastCoordinator.connectObsHostPreview(
                        token: start,
                        programPublisherIdentity: programId
                    )
                }
                startObsPolling(roomID: roomID, sessionId: sid)
                return
            }

            #if DEBUG
            TradeRoomObsBroadcastDiagnostics.log("ensure.start", roomID: roomID)
            #endif
            let start = try await client.startBroadcast(
                roomID: roomID,
                voiceMode: "broadcast_only",
                videoSource: "obs"
            )
            guard let sessionId = start.broadcastSessionId, !sessionId.isEmpty else {
                throw AppError.unknown(message: "Invalid broadcast start response.")
            }
            broadcastSessionId = sessionId
            broadcasterUserId = viewerUserId
            visibility = start.visibility ?? "preparing"
            publicDiscoverableLive = start.publicLive ?? false
            phase = .preparing
            rememberObsHostStartResponse(start, sessionId: sessionId)

            let programId = start.primaryMediaPublisherIdentity?.trimmingCharacters(in: .whitespacesAndNewlines)
            #if DEBUG
            TradeRoomObsBroadcastDiagnostics.log(
                "ensure.connectPreview",
                roomID: roomID,
                sessionId: sessionId
            )
            #endif
            try await broadcastCoordinator.connectObsHostPreview(
                token: start,
                programPublisherIdentity: programId
            )
            await loadCredentialsIfNeeded(
                roomID: roomID,
                sessionId: sessionId,
                status: nil,
                ingressFromStart: nil
            )
            startObsPolling(roomID: roomID, sessionId: sessionId)
        } catch {
            guard generation == ensurePrivateObsSessionGeneration else { return }
            if isCooperativeCancellation(error) {
                #if DEBUG
                TradeRoomObsBroadcastDiagnostics.log(
                    "ensure.cancelled",
                    roomID: roomID,
                    detail: String(describing: error)
                )
                #endif
                return
            }
            errorMessage = obsUserFacingError(error)
            await broadcastCoordinator.disconnectObsHostPreview()
        }
    }

    func copyRTMPURL() {
        guard let u = rtmpURL?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty else { return }
        UIPasteboard.general.string = u
    }

    func copyStreamKey() {
        guard let k = streamKey?.trimmingCharacters(in: .whitespacesAndNewlines), !k.isEmpty else { return }
        UIPasteboard.general.string = k
    }

    func publishToRoom(roomID: RoomID) async {
        guard let client, broadcastSessionId != nil else { return }
        guard TradeRoomObsGoLivePolicy.canGoLiveToRoom(
            isPreparingObs: phase == .preparing,
            isBusy: isBusy,
            encoderConnected: encoderConnected
        ) else {
            errorMessage = "OBS is not publishing yet. Start streaming in OBS and wait for the preview."
            return
        }
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await client.publishBroadcast(roomID: roomID)
            await broadcastCoordinator.refreshStatus(roomID: roomID)
            let status = try await client.fetchStatus(roomID: roomID, reconcile: true, lite: false)
            await applyStatus(status, roomID: roomID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func endStream(roomID: RoomID) async {
        guard let client else { return }
        cancelInFlightPrivateObsSessionEnsure()
        if broadcastSessionId == nil {
            await refreshFromServer(roomID: roomID)
        }
        guard let sessionId = broadcastSessionId else {
            errorMessage = "No active stream session to end."
            return
        }
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            try await client.stopBroadcast(roomID: roomID, sessionId: sessionId)
            await broadcastCoordinator.disconnectObsHostPreview()
            await broadcastCoordinator.leaveWatch()
            await broadcastCoordinator.refreshStatus(roomID: roomID)
            resetForDismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func regenerateStreamKey(roomID: RoomID) async {
        guard let client, let sessionId = broadcastSessionId else { return }
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            try await client.revokeObsIngress(roomID: roomID, sessionId: sessionId)
            await fetchCredentials(roomID: roomID, sessionId: sessionId)
            streamKeyRevealed = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Private

    private func applyStatus(_ status: LiveKitBroadcastStatusResponse, roomID: RoomID) async {
        visibility = status.visibility
        publicDiscoverableLive = status.publicLive ?? false
        broadcasterUserId = status.broadcasterUserId
        foreignHostPreparing = false

        let vis = status.visibility?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isObs = (status.videoSource == "obs") || (status.broadcastSource == "obs")

        guard let sessionId = status.broadcastSessionId, !sessionId.isEmpty else {
            phase = .idle
            broadcastSessionId = nil
            rtmpURL = nil
            streamKey = nil
            obsPollTask?.cancel()
            obsPollTask = nil
            syncObsHostBarSession()
            await disconnectObsHostPreviewUnlessPreserving(roomID: roomID)
            return
        }

        if publicDiscoverableLive || vis == "public" {
            broadcastSessionId = sessionId
            phase = .livePublic
            rtmpURL = nil
            streamKey = nil
            streamKeyRevealed = false
            obsPollTask?.cancel()
            obsPollTask = nil
            syncObsHostBarSession()
            await broadcastCoordinator.disconnectObsHostPreview()
            await broadcastCoordinator.refreshStatus(roomID: roomID)
            return
        }

        if isObs,
           vis == "preparing",
           let viewerUserId,
           let hostId = broadcasterUserId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !hostId.isEmpty,
           hostId != viewerUserId
        {
            foreignHostPreparing = true
            broadcastSessionId = nil
            phase = .idle
            rtmpURL = nil
            streamKey = nil
            streamKeyRevealed = false
            obsPollTask?.cancel()
            obsPollTask = nil
            syncObsHostBarSession()
            await broadcastCoordinator.disconnectObsHostPreview()
            if errorMessage == nil {
                errorMessage = "Another host is already preparing a stream for this room."
            }
            return
        }

        serverIngressId = status.livekitIngressId?.trimmingCharacters(in: .whitespacesAndNewlines)

        if isObs, vis == "preparing" {
            broadcastSessionId = sessionId
            phase = .preparing
        } else {
            phase = .idle
            syncObsHostBarSession()
            await disconnectObsHostPreviewUnlessPreserving(roomID: roomID)
        }
    }

    private func loadCredentialsIfNeeded(
        roomID: RoomID,
        sessionId: String,
        status: LiveKitBroadcastStatusResponse?,
        ingressFromStart: String? = nil
    ) async {
        let ingress =
            ingressFromStart?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? status?.livekitIngressId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? serverIngressId?.nilIfEmpty
        if let ingress, !ingress.isEmpty, rtmpURL == nil, streamKey == nil {
            errorMessage =
                "OBS credentials already exist for this session. Tap Regenerate stream key to issue a new key."
            return
        }
        await fetchCredentials(roomID: roomID, sessionId: sessionId)
    }

    private func fetchCredentials(roomID: RoomID, sessionId: String) async {
        if let obsCredentialsFlightSessionId,
           obsCredentialsFlightSessionId == sessionId,
           let obsCredentialsFlight,
           !obsCredentialsFlight.isCancelled
        {
            await obsCredentialsFlight.value
            return
        }

        if let ingress = serverIngressId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !ingress.isEmpty,
           rtmpURL != nil,
           streamKey != nil
        {
            return
        }

        obsCredentialsFlightSessionId = sessionId
        let flight = Task { @MainActor in
            await self.performFetchObsCredentials(roomID: roomID, sessionId: sessionId)
        }
        obsCredentialsFlight = flight
        await flight.value
        if obsCredentialsFlightSessionId == sessionId {
            obsCredentialsFlight = nil
        }
    }

    private func performFetchObsCredentials(roomID: RoomID, sessionId: String) async {
        guard let client else { return }
        #if DEBUG
        TradeRoomObsBroadcastDiagnostics.log("ensure.credentials", roomID: roomID, sessionId: sessionId)
        #endif
        do {
            let creds = try await client.createObsIngressCredentials(roomID: roomID, sessionId: sessionId)
            rtmpURL = creds.rtmpUrl
            streamKey = creds.streamKey
            serverIngressId = creds.livekitIngressId?.trimmingCharacters(in: .whitespacesAndNewlines)
            ingressStatusLabel = creds.ingressStatusSnapshot
            errorMessage = nil
        } catch {
            if isCooperativeCancellation(error) { return }
            let message = obsUserFacingError(error)
            if message.localizedCaseInsensitiveContains("already has OBS ingress")
                || message.localizedCaseInsensitiveContains("revoke")
            {
                errorMessage =
                    "OBS credentials already exist for this session. Tap Regenerate stream key to issue a new key."
                return
            }
            rtmpURL = nil
            streamKey = nil
            errorMessage = message
        }
    }

    private func startObsPolling(roomID: RoomID, sessionId: String) {
        obsPollTask?.cancel()
        obsPollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.pollObsOnce(roomID: roomID, sessionId: sessionId)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func pollObsOnce(roomID: RoomID, sessionId: String) async {
        guard let client else { return }
        do {
            let o = try await client.fetchObsStatus(roomID: roomID, sessionId: sessionId)
            await MainActor.run {
                self.ingressStatusLabel = o.ingressStatusSnapshot
                self.encoderConnected = o.primaryMediaPublisherConnected == true
                self.hostLiveKitConnected = o.hostConnected == true
            }
        } catch {
            guard !isCooperativeCancellation(error) else { return }
            await MainActor.run {
                if self.errorMessage == nil {
                    self.errorMessage = self.obsUserFacingError(error)
                }
            }
        }
    }

    private func isCooperativeCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let app = error as? AppError, case .cancelled = app { return true }
        if let net = error as? NetworkError, case .cancelled = net { return true }
        if let app = error as? AppError, case .transport(.cancelled) = app { return true }
        return false
    }

    private func obsUserFacingError(_ error: Error) -> String {
        if let app = error as? AppError {
            switch app {
            case .cancelled:
                return "Setup was interrupted. Close this sheet and tap Start Stream again."
            case .unknown(let message):
                return message
            case .transport(let network):
                return obsUserFacingNetworkError(network)
            case .authentication:
                return "Sign in again to manage streams."
            case .notImplemented(let feature):
                return "Not implemented: \(feature)"
            }
        }
        if let net = error as? NetworkError {
            return obsUserFacingNetworkError(net)
        }
        return error.localizedDescription
    }

    private func obsUserFacingNetworkError(_ error: NetworkError) -> String {
        switch error {
        case .cancelled:
            return "Setup was interrupted. Close this sheet and tap Start Stream again."
        case .unauthorized, .forbidden:
            return "Sign in again to manage streams."
        case .validation(_, let message):
            return message
        case .server(let code, let message):
            if let message, !message.isEmpty { return message }
            return "Server error (HTTP \(code))."
        case .connectivity:
            return "You're offline. Check your connection and try again."
        case .timeout:
            return "The request timed out. Try again."
        case .rateLimited:
            return "Too many requests. Wait a moment and try again."
        case .decoding(let message):
            return "Invalid server response. \(message)"
        case .unknown(let message):
            return message
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

enum TradeRoomObsGoLivePolicy {
    /// Mirrors web `tradeRoomObsGoLiveToRoomEnabled` — preparing host, not busy, encoder connected.
    static func canGoLiveToRoom(
        isPreparingObs: Bool,
        isBusy: Bool,
        encoderConnected: Bool
    ) -> Bool {
        isPreparingObs && !isBusy && encoderConnected
    }
}
