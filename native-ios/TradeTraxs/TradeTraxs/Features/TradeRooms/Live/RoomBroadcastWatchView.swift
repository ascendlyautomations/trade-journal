import SwiftUI

struct RoomBroadcastWatchView: View {
    let roomID: RoomID
    let roomTitle: String
    let userId: String?
    let displayName: String
    let imagePipeline: any ImagePipeline
    @Bindable var coordinator: RoomBroadcastCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors

    @State private var chatDraft = ""
    @State private var showsParticipants = false
    @State private var isFullscreen = false
    @State private var isChatComposerFocused = false
    @State private var isTypingMiniPlayerDismissed = false
    @State private var isViewerVideoCornerPinned = false

    private var usesCornerVideo: Bool {
        isChatComposerFocused || isViewerVideoCornerPinned
    }

    private var cornerPlayerSize: RoomBroadcastCornerPlayerSize {
        isChatComposerFocused ? .standard : .compact
    }

    var body: some View {
        VStack(spacing: 0) {
            streamHeader
            if !usesCornerVideo {
                RoomBroadcastStudioVideoSection(
                    coordinator: coordinator,
                    isFullscreen: $isFullscreen
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let error = coordinator.lastError {
                Text(error)
                    .experienceStyle(.caption, color: colors.error)
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.vertical, ExperienceSpacing.xxs)
            }
            ZStack(alignment: .topTrailing) {
                RoomBroadcastStudioChatPane(
                    coordinator: coordinator,
                    imagePipeline: imagePipeline,
                    userId: userId,
                    displayName: displayName,
                    chatDraft: $chatDraft,
                    useViewerKeyboardChrome: true,
                    composerFocusedBinding: $isChatComposerFocused
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if usesCornerVideo, !isTypingMiniPlayerDismissed {
                    RoomBroadcastChatTypingMiniPlayerOverlay(
                        coordinator: coordinator,
                        isDismissed: $isTypingMiniPlayerDismissed,
                        size: cornerPlayerSize,
                        onExpand: isViewerVideoCornerPinned && !isChatComposerFocused
                            ? { withAnimation(.snappy(duration: 0.28)) { isViewerVideoCornerPinned = false } }
                            : nil
                    )
                } else if usesCornerVideo, isTypingMiniPlayerDismissed {
                    cornerVideoDismissedPlaceholder
                }
            }
            .frame(maxHeight: .infinity)
            if !isChatComposerFocused {
                streamToolbar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.28), value: isChatComposerFocused)
        .animation(.snappy(duration: 0.28), value: isViewerVideoCornerPinned)
        .animation(.snappy(duration: 0.28), value: isTypingMiniPlayerDismissed)
        .onChange(of: isChatComposerFocused) { _, focused in
            guard !focused else { return }
            isTypingMiniPlayerDismissed = false
        }
        .onChange(of: isViewerVideoCornerPinned) { _, pinned in
            if pinned {
                isTypingMiniPlayerDismissed = false
            }
        }
        .onChange(of: usesCornerVideo) { _, corner in
            syncProgramVideoSurfaceForLayout(cornerVideo: corner, fullscreen: isFullscreen)
        }
        .onChange(of: isTypingMiniPlayerDismissed) { _, _ in
            syncProgramVideoSurfaceForLayout(cornerVideo: usesCornerVideo, fullscreen: isFullscreen)
        }
        .onChange(of: isFullscreen) { _, full in
            syncProgramVideoSurfaceForLayout(cornerVideo: usesCornerVideo, fullscreen: full)
        }
        .onAppear {
            syncProgramVideoSurfaceForLayout(cornerVideo: usesCornerVideo, fullscreen: isFullscreen)
        }
        .background(colors.primaryBackground)
        .fullScreenCover(isPresented: $isFullscreen) {
            fullscreenPlayer
        }
        .sheet(isPresented: $showsParticipants) {
            RoomBroadcastParticipantsSheet(
                coordinator: coordinator,
                imagePipeline: imagePipeline
            )
        }
        .task {
            if !coordinator.isWatchingRoom(roomID) {
                await coordinator.watch(roomID: roomID, roomTitle: roomTitle)
            } else {
                coordinator.presentViewer()
            }
        }
        .task(id: coordinator.chatMessages.map(\.id)) {
            let ids = coordinator.chatMessages.map(\.userId)
            await coordinator.chatProfileCache.hydrate(userIds: ids)
            let rosterIds = coordinator.rosterParticipants.map(\.identity)
            await coordinator.chatProfileCache.hydrate(userIds: rosterIds)
        }
        .task(id: coordinator.chatMessages.compactMap { $0.tradeID?.rawValue }.sorted().joined(separator: ",")) {
            await coordinator.hydrateBroadcastChatTradesIfNeeded()
        }
        .onChange(of: coordinator.streamFullscreenDismissSignal) { _, _ in
            isFullscreen = false
        }
        .onChange(of: coordinator.streamEndedNotice?.id) { _, noticeID in
            if noticeID != nil {
                isFullscreen = false
                dismiss()
            }
        }
        .onChange(of: coordinator.streamRemovalNotice?.id) { _, noticeID in
            if noticeID != nil {
                isFullscreen = false
                dismiss()
            }
        }
        .overlay {
            if let notice = coordinator.speakInviteNotice {
                BroadcastSpeakInviteOverlay(notice: notice, coordinator: coordinator)
                    .zIndex(100_000)
            }
        }
        .animation(.snappy(duration: 0.28), value: coordinator.speakInviteNotice?.id)
    }

    private var streamHeader: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            Button {
                coordinator.minimizeViewer()
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(colors.primaryText)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.experiencePlain)
            .accessibilityLabel("Minimize")

            VStack(alignment: .leading, spacing: 2) {
                Text(
                    TradeRoomBroadcastStreamTitle.viewerPopupHeadline(
                        streamTitle: coordinator.polledStatus.streamTitle,
                        roomName: roomTitle
                    )
                )
                .experienceStyle(.subheadline, color: colors.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                HStack(spacing: 6) {
                    Text("LIVE")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule(style: .continuous).fill(Color.red.opacity(0.9)))
                    Text(coordinator.broadcastStatusLabel)
                        .experienceStyle(.caption2, color: colors.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                toggleCornerVideoPin()
            } label: {
                Image(systemName: isViewerVideoCornerPinned ? "pip.exit" : "pip.enter")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(
                        isViewerVideoCornerPinned ? colors.accent : colors.primaryText
                    )
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.experiencePlain)
            .accessibilityLabel(isViewerVideoCornerPinned ? "Expand video" : "Minimize video for chat")

            Button {
                showsParticipants = true
            } label: {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(colors.primaryText)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.experiencePlain)
            .accessibilityLabel("Participants")
        }
        .padding(.horizontal, ExperienceSpacing.sm)
        .padding(.vertical, ExperienceSpacing.xs)
        .background(colors.navigationBackground.opacity(0.98))
        .contentShape(Rectangle())
        .simultaneousGesture(headerMinimizeDragGesture)
    }

    private var cornerVideoDismissedPlaceholder: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func syncProgramVideoSurfaceForLayout(cornerVideo: Bool, fullscreen: Bool) {
        if fullscreen {
            coordinator.adoptProgramVideoSurface(.sheetFullscreen)
        } else if cornerVideo {
            coordinator.adoptProgramVideoSurface(
                isTypingMiniPlayerDismissed ? .cornerDismissedHold : .cornerChat
            )
        } else {
            coordinator.adoptProgramVideoSurface(.inlineExpanded)
        }
    }

    private func toggleCornerVideoPin() {
        ExperienceHaptics.play(.selection)
        withAnimation(.snappy(duration: 0.28)) {
            isViewerVideoCornerPinned.toggle()
            if isViewerVideoCornerPinned {
                isTypingMiniPlayerDismissed = false
            }
        }
    }

    private var headerMinimizeDragGesture: some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .local)
            .onEnded { value in
                let vertical = value.translation.height
                let horizontal = abs(value.translation.width)
                let velocityY = value.predictedEndTranslation.height - value.translation.height
                let shouldMinimize =
                    vertical > 0
                    && vertical > horizontal * 1.05
                    && (vertical >= 72 || velocityY >= 900)
                guard shouldMinimize else { return }
                coordinator.minimizeViewer()
                dismiss()
            }
    }

    private var streamToolbar: some View {
        HStack(spacing: 0) {
            toolbarIcon(
                systemName: coordinator.isBroadcastHandRaised ? "hand.raised.fill" : "hand.raised",
                label: coordinator.isBroadcastHandRaised ? "Lower hand" : "Raise hand",
                tint: coordinator.isBroadcastHandRaised ? colors.accent : colors.primaryText
            ) {
                Task { await coordinator.toggleBroadcastHand() }
            }

            RoomBroadcastAudioControl(coordinator: coordinator, style: .toolbar)

            if coordinator.isInConversation {
                toolbarIcon(
                    systemName: coordinator.isMicrophoneEnabledInStream ? "mic.fill" : "mic.slash.fill",
                    label: coordinator.isMicrophoneEnabledInStream ? "Mute mic" : "Unmute mic",
                    tint: coordinator.isMicrophoneEnabledInStream ? colors.primaryText : colors.error
                ) {
                    Task { await coordinator.toggleStreamMicrophone() }
                }
            }

            toolbarIcon(
                systemName: "person.2.fill",
                label: "Participants",
                tint: colors.primaryText
            ) {
                showsParticipants = true
            }

            Spacer(minLength: 0)

            Button {
                Task {
                    await coordinator.leaveWatch()
                    dismiss()
                }
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(colors.error))
            }
            .buttonStyle(.experiencePlain)
            .accessibilityLabel("Leave stream")
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.top, ExperienceSpacing.xs)
        .padding(.bottom, ExperienceSpacing.sm)
        .background(colors.navigationBackground.opacity(0.98))
    }

    private var fullscreenPlayer: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            BroadcastStreamZoomableVideoView(
                track: coordinator.videoTrackForExpandedViewer,
                trackRevision: coordinator.programVideoTrackRevision,
                isFullscreen: true,
                onFirstFrame: { coordinator.markProgramVideoFrameRendered() }
            )
            .id(coordinator.programVideoRendererIdentity)
            .opacity(coordinator.hasDisplayableProgramVideo ? 1 : 0)
            .ignoresSafeArea()

            if let placeholder = coordinator.programVideoPlaceholder {
                BroadcastProgramVideoPlaceholderOverlay(presentation: placeholder)
                    .ignoresSafeArea()
            }

            VStack(spacing: ExperienceSpacing.sm) {
                HStack {
                    Spacer()
                    Button {
                        isFullscreen = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.black.opacity(0.45))
                    }
                    .buttonStyle(.experiencePlain)
                    .accessibilityLabel("Exit fullscreen")
                }
                Spacer()
                HStack(spacing: ExperienceSpacing.lg) {
                    RoomBroadcastAudioControl(coordinator: coordinator, style: .fullscreen)
                    fullscreenControl(systemName: "hand.raised.fill") {
                        Task { await coordinator.toggleBroadcastHand() }
                    }
                }
                .padding(.bottom, ExperienceSpacing.xl)
            }
            .padding(ExperienceSpacing.md)

            if let notice = coordinator.speakInviteNotice {
                BroadcastSpeakInviteOverlay(notice: notice, coordinator: coordinator)
                    .zIndex(100_000)
            }
        }
    }

    private func toolbarIcon(
        systemName: String,
        label: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemName)
                    .font(.system(size: 18, weight: .semibold))
                Text(label.split(separator: " ").first.map(String.init) ?? label)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
            .frame(minWidth: 52)
            .padding(.vertical, 4)
        }
        .buttonStyle(.experiencePlain)
        .accessibilityLabel(label)
    }

    private func fullscreenControl(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Color.white.opacity(0.15)))
        }
        .buttonStyle(.experiencePlain)
    }

}