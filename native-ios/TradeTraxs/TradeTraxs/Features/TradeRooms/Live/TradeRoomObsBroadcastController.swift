import LiveKit
import Observation
import SwiftUI
import UIKit

/// Owner-only OBS broadcast control — BFF + LiveKit preview subscribe only (no iOS camera/mic capture).
@Observable
@MainActor
final class TradeRoomObsBroadcastController {
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

    func configure(viewerUserId: String?, transport: SupabaseTransport?) {
        self.viewerUserId = viewerUserId
        if let transport {
            client = LiveKitBroadcastClient(transport: transport)
        } else {
            client = nil
        }
    }

    func resetForDismiss() {
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
        Task { await broadcastCoordinator.disconnectObsHostPreview() }
    }

    /// Reconcile room state from server (existing preparing/public session, or idle).
    func refreshFromServer(roomID: RoomID) async {
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

    /// Ensure a private OBS session exists and this device is connected for preview + credentials.
    func ensurePrivateObsSession(roomID: RoomID) async {
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
        defer { isBusy = false }

        do {
            #if DEBUG
            TradeRoomObsBroadcastDiagnostics.log("ensure.status", roomID: roomID)
            #endif
            let status = try await client.fetchStatus(roomID: roomID, reconcile: true, lite: false)
            await applyStatus(status, roomID: roomID)

            if phase == .livePublic {
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
                    let start = try await client.startBroadcast(
                        roomID: roomID,
                        voiceMode: "broadcast_only",
                        videoSource: "obs"
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
            if isCooperativeCancellation(error) {
                #if DEBUG
                TradeRoomObsBroadcastDiagnostics.log(
                    "ensure.cancelled",
                    roomID: roomID,
                    detail: String(describing: error)
                )
                #endif
                errorMessage =
                    "Setup was interrupted. Close this sheet and tap Start Stream again."
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
        guard let client, let sessionId = broadcastSessionId else {
            resetForDismiss()
            return
        }
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            try await client.stopBroadcast(roomID: roomID, sessionId: sessionId)
            await broadcastCoordinator.disconnectObsHostPreview()
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
            await broadcastCoordinator.disconnectObsHostPreview()
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
            await broadcastCoordinator.disconnectObsHostPreview()
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
            rtmpURL = nil
            streamKey = nil
            errorMessage = obsUserFacingError(error)
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
