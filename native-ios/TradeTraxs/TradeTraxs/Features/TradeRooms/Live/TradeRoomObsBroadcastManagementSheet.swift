import SwiftUI

struct TradeRoomObsBroadcastManagementSheet: View {
    let roomID: RoomID
    let roomTitle: String
    @Bindable var controller: TradeRoomObsBroadcastController
    @Bindable var broadcastCoordinator: RoomBroadcastCoordinator
    let imagePipeline: any ImagePipeline
    let chatUserId: String?
    let chatDisplayName: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors

    var body: some View {
        Group {
            if showsLiveManageLayout {
                TradeRoomObsLiveManageStreamView(
                    roomID: roomID,
                    roomTitle: roomTitle,
                    controller: controller,
                    broadcastCoordinator: broadcastCoordinator,
                    imagePipeline: imagePipeline,
                    chatUserId: chatUserId,
                    chatDisplayName: chatDisplayName,
                    onClose: closeSheet
                )
            } else {
                preparingShell
            }
        }
        .task(id: roomID.rawValue) {
            controller.startPrivateObsSessionEnsureIfNeeded(roomID: roomID)
            await controller.ensurePrivateObsSession(roomID: roomID)
        }
        .task(id: liveHostWatchTaskID) {
            guard controller.phase == .livePublic else { return }
            await broadcastCoordinator.watch(roomID: roomID, roomTitle: roomTitle)
        }
        .task(id: broadcastCoordinator.chatMessages.map(\.id)) {
            let ids = broadcastCoordinator.chatMessages.map(\.userId)
            await broadcastCoordinator.chatProfileCache.hydrate(userIds: ids)
            let rosterIds = broadcastCoordinator.rosterParticipants.map(\.identity)
            await broadcastCoordinator.chatProfileCache.hydrate(userIds: rosterIds)
        }
    }

    private var showsLiveManageLayout: Bool {
        controller.phase == .livePublic && !showsObsInitializingPlaceholder
    }

    private var liveHostWatchTaskID: String {
        "live-host-watch-\(roomID.rawValue)-\(controller.phase == .livePublic)"
    }

    private func closeSheet() {
        if controller.phase == .idle {
            controller.resetForDismiss()
        } else {
            controller.acknowledgeManagementSheetDismissed()
        }
        broadcastCoordinator.setObsManageStreamPresented(false)
        dismiss()
    }

    private var preparingShell: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                    if showsObsInitializingPlaceholder {
                        initializingSection
                    } else {
                        switch controller.phase {
                        case .livePublic:
                            EmptyView()
                        case .preparing:
                            preparingSection
                        case .idle:
                            if controller.foreignHostPreparing {
                                foreignHostSection
                            } else {
                                idleSection
                            }
                        }
                    }

                    if let err = controller.errorMessage, !err.isEmpty, !showsObsInitializingPlaceholder {
                        Text(err)
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(colors.error)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(ExperienceSpacing.md)
            }
            .background(colors.primaryBackground)
            .navigationTitle(obsNavigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(controller.phase == .preparing ? "Cancel" : "Close") {
                        closeSheet()
                    }
                }
            }
        }
    }

    private var showsObsInitializingPlaceholder: Bool {
        controller.isEnsuringPrivateObsSession
            && controller.phase == .idle
            && !controller.foreignHostPreparing
    }

    private var obsNavigationTitle: String {
        if controller.phase == .preparing || showsObsInitializingPlaceholder {
            return "Preparing OBS"
        }
        return roomTitle
    }

    private var initializingSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack(spacing: ExperienceSpacing.sm) {
                ProgressView()
                Text("Preparing OBS...")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preparing OBS")
    }

    private var idleSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("No active OBS preparation session for this room.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(colors.textSecondary)
        }
    }

    private var foreignHostSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text(
                "Another host is already preparing a stream for this room. Close this sheet and try again when that session ends."
            )
            .font(.system(.subheadline, design: .rounded))
            .foregroundStyle(colors.textSecondary)
        }
    }

    private var preparingSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            Text("Private setup — stream is not visible to the room until you tap Go live to room.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(colors.textSecondary)

            obsInstructions

            if let url = controller.rtmpURL, !url.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Server (RTMP URL)")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(colors.textSecondary)
                    Text(url)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(colors.textPrimary)
                        .textSelection(.enabled)
                    Button("Copy URL") {
                        controller.copyRTMPURL()
                    }
                    .buttonStyle(.bordered)
                }
            }

            streamKeyRow

            statusRow

            if let track = broadcastCoordinator.obsHostPreviewVideoTrack {
                Text("Preview")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(colors.textSecondary)
                LiveKitBroadcastVideoView(track: track)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
            }

            HStack(spacing: ExperienceSpacing.sm) {
                Button("Regenerate stream key") {
                    Task { await controller.regenerateStreamKey(roomID: roomID) }
                }
                .buttonStyle(.bordered)
                .disabled(controller.isBusy)
            }

            Button("Go live to room") {
                Task { await controller.publishToRoom(roomID: roomID) }
            }
            .buttonStyle(.borderedProminent)
            .tint(colors.accent)
            .disabled(
                !TradeRoomObsGoLivePolicy.canGoLiveToRoom(
                    isPreparingObs: true,
                    isBusy: controller.isBusy,
                    encoderConnected: controller.encoderConnected
                )
            )

            Button("End stream", role: .destructive) {
                Task {
                    await controller.endStream(roomID: roomID)
                    dismiss()
                }
            }
            .disabled(controller.isBusy)
        }
    }

    private var streamKeyRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Stream key")
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(colors.textSecondary)
            if let key = controller.streamKey, !key.isEmpty {
                if controller.streamKeyRevealed {
                    Text(key)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(colors.textPrimary)
                        .textSelection(.enabled)
                } else {
                    Text(String(repeating: "•", count: min(key.count, 32)))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(colors.textSecondary)
                }
                HStack {
                    Button(controller.streamKeyRevealed ? "Hide" : "Show") {
                        controller.streamKeyRevealed.toggle()
                    }
                    .buttonStyle(.bordered)
                    Button("Copy") {
                        controller.copyStreamKey()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!controller.streamKeyRevealed)
                }
            } else {
                Text("Credentials missing — use Regenerate stream key after revoking.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
            }
        }
    }

    private var statusRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Connection")
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(colors.textSecondary)
            Text("Host in LiveKit: \(controller.hostLiveKitConnected ? "Connected" : "…")")
                .font(.system(.caption, design: .rounded))
            Text("OBS encoder: \(controller.encoderConnected ? "Connected" : "Waiting…")")
                .font(.system(.caption, design: .rounded))
            if let snap = controller.ingressStatusLabel, !snap.isEmpty {
                Text("Ingress: \(snap)")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
            }
        }
    }

    private var obsInstructions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Configure OBS")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
            Text(
                """
                In OBS: Settings → Stream. Set Service to Custom… . Paste the server URL and stream key, then click Start Streaming in OBS.
                """
            )
            .font(.system(.footnote, design: .rounded))
            .foregroundStyle(colors.textSecondary)
        }
        .padding(ExperienceSpacing.sm)
        .background(colors.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
    }
}
