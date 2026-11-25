import SwiftUI

struct TradeRoomObsBroadcastManagementSheet: View {
    let roomID: RoomID
    let roomTitle: String
    @Bindable var controller: TradeRoomObsBroadcastController
    @Bindable var broadcastCoordinator: RoomBroadcastCoordinator
    let imagePipeline: any ImagePipeline
    let chatUserId: String?
    let chatDisplayName: String
    @State private var streamTitleDraft: String = ""
    @State private var configurationInstructionsExpanded = false
    @State private var showsEndStreamConfirmation = false
    @State private var inlineCopyFeedback: ObsCredentialCopyFeedback?
    @State private var inlineCopyHideTask: Task<Void, Never>?

    private enum ObsCredentialCopyFeedback: Equatable {
        case rtmpURL
        case streamKey
    }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            controller.ensureObsEncoderPolling(roomID: roomID)
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
        broadcastCoordinator.dismissObsManageStreamPreservingBroadcast()
        dismiss()
    }

    private func cancelPreparingObs() {
        Task {
            await controller.cancelObsPreparation(roomID: roomID)
            broadcastCoordinator.setObsManageStreamPresented(false)
            dismiss()
        }
    }

    private var preparingShell: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                    if showsObsInitializingPlaceholder {
                        streamSetupCard { initializingSection }
                    } else {
                        switch controller.phase {
                        case .livePublic:
                            streamSetupCard { goingLiveSection }
                        case .preparing:
                            preparingSection
                        case .idle:
                            if controller.foreignHostPreparing {
                                streamSetupCard { foreignHostSection }
                            } else {
                                streamSetupCard { idleSection }
                            }
                        }
                    }

                    if let err = controller.errorMessage, !err.isEmpty, !showsObsInitializingPlaceholder {
                        streamSetupCard {
                            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                                Text(err)
                                    .font(.system(.footnote, design: .rounded))
                                    .foregroundStyle(colors.error)
                                Button("Try again") {
                                    controller.retryPrivateObsSessionEnsure(roomID: roomID)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(colors.accent)
                                .disabled(controller.isBusy)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.top, ExperienceSpacing.sm)
                .padding(.bottom, showsPreparingBottomActions ? ExperienceSpacing.lg : ExperienceSpacing.xl)
            }
            .experienceScreenBackground(usesGroupedFillInLightMode: true)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showsPreparingBottomActions {
                    preparingObsBottomActionsFooter
                }
            }
            .navigationTitle(obsNavigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(controller.phase == .preparing ? "Cancel" : "Close") {
                        if controller.phase == .preparing {
                            cancelPreparingObs()
                        } else {
                            closeSheet()
                        }
                    }
                }
            }
            .broadcastObsConnectedOverlay(
                isPresented: controller.showsObsConnectedPrompt,
                onStartStream: {
                    Task { await controller.confirmObsConnectedStartStream(roomID: roomID) }
                },
                onNotYet: { controller.dismissObsConnectedPrompt() }
            )
            .confirmationDialog(
                "End Stream?",
                isPresented: $showsEndStreamConfirmation,
                titleVisibility: .visible
            ) {
                Button("End Stream", role: .destructive) {
                    Task {
                        await controller.endStream(roomID: roomID)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to end this stream?")
            }
        }
    }

    private var showsPreparingBottomActions: Bool {
        controller.phase == .preparing && !showsObsInitializingPlaceholder
    }

    private var preparingObsPageBackground: Color {
        if colorScheme == .light {
            return colors.groupedBackground
        }
        return colors.primaryBackground
    }

    private var preparingObsBottomActionsFooter: some View {
        VStack(spacing: 0) {
            TradeRoomObsBroadcastBottomActions(
                showsGoLive: true,
                goLiveEnabled: controller.streamReadyForGoLive,
                endStreamEnabled: !controller.isBusy && controller.broadcastSessionId != nil,
                onGoLive: {
                    Task { await controller.publishToRoom(roomID: roomID) }
                },
                onEndStream: { showsEndStreamConfirmation = true },
                embedsBarBackground: false
            )
            .padding(.top, ExperienceSpacing.xs)
        }
        .frame(maxWidth: .infinity)
        .safeAreaPadding(.bottom, ExperienceSpacing.xs)
        .background {
            preparingObsPageBackground
                .ignoresSafeArea(edges: .bottom)
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
            Button("Set up OBS") {
                controller.retryPrivateObsSessionEnsure(roomID: roomID)
            }
            .buttonStyle(.borderedProminent)
            .tint(colors.accent)
            .disabled(controller.isBusy || controller.isEnsuringPrivateObsSession)
        }
    }

    private var goingLiveSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack(spacing: ExperienceSpacing.sm) {
                ProgressView()
                Text("Opening live stream controls…")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Opening live stream controls")
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
            streamSetupSection(title: "Stream title") {
                streamTitleEditor
            }

            streamSetupSection(title: "Setup") {
                Text("Private setup, stream is not visible to the room until you tap Go live to room.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                configurationInstructionsDisclosure
            }

            streamSetupSection(title: "OBS credentials") {
                VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                    if let url = controller.rtmpURL, !url.isEmpty {
                        rtmpCredentialBlock(url: url)
                        obsCredentialDivider
                    }
                    streamKeyRow
                }
            }

            streamSetupSection(title: "Connection") {
                statusRow
            }

            if let track = broadcastCoordinator.obsHostPreviewVideoTrack {
                streamSetupSection(title: "Preview") {
                    LiveKitBroadcastVideoView(track: track)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
                }
            }

        }
    }

    private var configurationInstructionsDisclosure: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Button {
                ExperienceHaptics.play(.selection)
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    configurationInstructionsExpanded.toggle()
                }
            } label: {
                HStack(spacing: ExperienceSpacing.sm) {
                    Text("Configuration instructions")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(colors.primaryText)
                    Spacer(minLength: 0)
                    Image(systemName: configurationInstructionsExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(colors.tertiaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.experiencePlain)
            .accessibilityLabel("Configuration instructions")
            .accessibilityValue(configurationInstructionsExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Double tap to \(configurationInstructionsExpanded ? "collapse" : "expand")")

            if configurationInstructionsExpanded {
                obsInstructions
            }
        }
        .padding(ExperienceSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tradingRulesNestedGroup()
    }

    private var obsCredentialDivider: some View {
        Rectangle()
            .fill(colors.border.opacity(0.45))
            .frame(height: ExperienceBorder.hairline)
    }

    private func rtmpCredentialBlock(url: String) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text("Server (RTMP URL)")
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(colors.textSecondary)
            Text(url)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(colors.textPrimary)
                .textSelection(.enabled)
                .padding(ExperienceSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .tradingRulesNestedGroup()
            HStack(spacing: ExperienceSpacing.sm) {
                Button("Copy URL") {
                    if controller.copyRTMPURL(showsConfirmationToast: false) {
                        showInlineCopyFeedback(.rtmpURL)
                    }
                }
                .buttonStyle(.bordered)
                if inlineCopyFeedback == .rtmpURL {
                    obsInlineCopiedLabel
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func streamSetupSection<Content: View>(
        title: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            if let title, !title.isEmpty {
                Text(title)
                    .experienceStyle(.headline, color: colors.primaryText)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                content()
            }
            .padding(ExperienceSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .experienceTradingRulesCard(prominence: .standard)
        }
    }

    private func streamSetupCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            content()
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceTradingRulesCard(prominence: .standard)
    }

    private var streamKeyRow: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Stream key")
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(colors.textSecondary)

            if let key = controller.streamKey, !key.isEmpty {
                Group {
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
                }
                .padding(ExperienceSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .tradingRulesNestedGroup()

                HStack(spacing: ExperienceSpacing.sm) {
                    Button(controller.streamKeyRevealed ? "Hide" : "Show") {
                        controller.streamKeyRevealed.toggle()
                    }
                    .buttonStyle(.bordered)

                    Button("Copy Stream Key") {
                        if controller.copyStreamKey(showsConfirmationToast: false) {
                            showInlineCopyFeedback(.streamKey)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!controller.streamKeyRevealed)

                    if inlineCopyFeedback == .streamKey {
                        obsInlineCopiedLabel
                    }

                    Spacer(minLength: 0)
                }

                Button("Regenerate stream key") {
                    Task { await controller.regenerateStreamKey(roomID: roomID) }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(controller.isBusy)
            } else {
                Text("Credentials missing, use Regenerate stream key after revoking.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Regenerate stream key") {
                    Task { await controller.regenerateStreamKey(roomID: roomID) }
                }
                .buttonStyle(.bordered)
                .disabled(controller.isBusy)
            }
        }
    }

    private var statusRow: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
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

    private var streamTitleEditor: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            TextField("e.g. Trading NY Session, NQ Futures", text: $streamTitleDraft)
                .textInputAutocapitalization(.sentences)
                .tradingRulesInsetControl()
                .onAppear {
                    streamTitleDraft = controller.streamTitle ?? streamTitleDraft
                }
                .onChange(of: controller.streamTitle) { _, newValue in
                    if streamTitleDraft.isEmpty, let newValue {
                        streamTitleDraft = newValue
                    }
                }
            HStack {
                Text("\(streamTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines).count)/\(TradeRoomBroadcastStreamTitle.maxLength)")
                    .font(.caption2)
                    .foregroundStyle(colors.textSecondary)
                Spacer()
                Button("Save title") {
                    Task { await controller.updateStreamTitle(roomID: roomID, draft: streamTitleDraft) }
                }
                .font(.caption.weight(.semibold))
                .disabled(controller.isBusy)
            }
        }
    }

    private var obsInlineCopiedLabel: some View {
        HStack(spacing: ExperienceSpacing.xxs) {
            Text("Copied")
                .font(.caption.weight(.semibold))
            Image(systemName: "checkmark")
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(colors.profit)
        .accessibilityLabel("Copied")
    }

    private func showInlineCopyFeedback(_ kind: ObsCredentialCopyFeedback) {
        inlineCopyHideTask?.cancel()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
            inlineCopyFeedback = kind
        }
        inlineCopyHideTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                    if inlineCopyFeedback == kind {
                        inlineCopyFeedback = nil
                    }
                }
            }
        }
    }

    private var obsInstructions: some View {
        Text(
            """
            In OBS: Settings → Stream. Set Service to Custom… . Paste the server URL and stream key, then click Start Streaming in OBS.
            """
        )
        .font(.system(.footnote, design: .rounded))
        .foregroundStyle(colors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
