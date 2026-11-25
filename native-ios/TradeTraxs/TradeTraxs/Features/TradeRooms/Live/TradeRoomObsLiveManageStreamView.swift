import SwiftUI

/// OBS live host UI, viewer-style video + tabbed chat / members / hands.
struct TradeRoomObsLiveManageStreamView: View {
    let roomID: RoomID
    let roomTitle: String
    @Bindable var controller: TradeRoomObsBroadcastController
    @Bindable var broadcastCoordinator: RoomBroadcastCoordinator
    let imagePipeline: any ImagePipeline
    let chatUserId: String?
    let chatDisplayName: String
    var onClose: () -> Void
    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var chatDraft = ""
    @State private var selectedTab: RoomBroadcastStudioHostTab = .chat
    @State private var isFullscreen = false
    @State private var showsEndStreamConfirmation = false
    @State private var isChatComposerFocused = false
    @State private var isTypingMiniPlayerDismissed = false
    @State private var isHostVideoCornerPinned = false

    private var usesCornerVideo: Bool {
        isChatComposerFocused || isHostVideoCornerPinned
    }

    private var cornerPlayerSize: RoomBroadcastCornerPlayerSize {
        isChatComposerFocused ? .standard : .compact
    }

    var body: some View {
        VStack(spacing: 0) {
            manageHeader
            RoomBroadcastStudioHostTabBar(
                selectedTab: $selectedTab,
                memberCount: tabMemberCount,
                raisedHandCount: tabRaisedHandCount
            )
            if !usesCornerVideo {
                RoomBroadcastStudioVideoSection(
                    coordinator: broadcastCoordinator,
                    isFullscreen: $isFullscreen,
                    showsPictureInPictureControl: true,
                    isPictureInPictureActive: isHostVideoCornerPinned,
                    onTogglePictureInPicture: toggleCornerVideoPin
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let banner = statusBannerMessage {
                Text(banner)
                    .experienceStyle(.caption, color: colors.error)
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.vertical, ExperienceSpacing.xxs)
            }
            ZStack(alignment: .topTrailing) {
                RoomBroadcastStudioHostSidebar(
                    roomID: roomID,
                    isHostBroadcaster: true,
                    embedsTabBar: false,
                    broadcasterUserId: broadcastCoordinator.polledStatus.broadcasterUserId,
                    coordinator: broadcastCoordinator,
                    imagePipeline: imagePipeline,
                    userId: chatUserId,
                    displayName: chatDisplayName,
                    chatDraft: $chatDraft,
                    selectedTab: $selectedTab,
                    useViewerKeyboardChrome: selectedTab == .chat,
                    composerFocusedBinding: $isChatComposerFocused
                )

                if usesCornerVideo, !isTypingMiniPlayerDismissed {
                    RoomBroadcastChatTypingMiniPlayerOverlay(
                        coordinator: broadcastCoordinator,
                        isDismissed: $isTypingMiniPlayerDismissed,
                        size: cornerPlayerSize,
                        onExpand: isHostVideoCornerPinned && !isChatComposerFocused
                            ? { unpinnedCornerVideo() }
                            : nil
                    )
                } else if usesCornerVideo, isTypingMiniPlayerDismissed {
                    cornerVideoDismissedPlaceholder
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.snappy(duration: 0.28), value: isChatComposerFocused)
        .animation(.snappy(duration: 0.28), value: isHostVideoCornerPinned)
        .animation(.snappy(duration: 0.28), value: isTypingMiniPlayerDismissed)
        .background(colors.primaryBackground)
        .fullScreenCover(isPresented: $isFullscreen) {
            fullscreenPlayer
        }
        .confirmationDialog(
            "End Stream?",
            isPresented: $showsEndStreamConfirmation,
            titleVisibility: .visible
        ) {
            Button("End Stream", role: .destructive) {
                Task {
                    await controller.endStream(roomID: roomID)
                    onClose()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to end this stream?")
        }
        .onChange(of: broadcastCoordinator.streamEndedNotice?.id) { _, noticeID in
            if noticeID != nil {
                isFullscreen = false
                onClose()
            }
        }
        .onChange(of: selectedTab) { _, tab in
            if tab != .chat {
                isChatComposerFocused = false
            }
        }
        .onChange(of: isChatComposerFocused) { _, focused in
            guard !focused else { return }
            isTypingMiniPlayerDismissed = false
        }
        .onChange(of: isHostVideoCornerPinned) { _, pinned in
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
            if broadcastCoordinator.isWatching, broadcastCoordinator.viewerPresentation == .off {
                broadcastCoordinator.presentViewer()
            }
            syncProgramVideoSurfaceForLayout(cornerVideo: usesCornerVideo, fullscreen: isFullscreen)
        }
        .overlay {
            if let notice = broadcastCoordinator.speakInviteNotice {
                BroadcastSpeakInviteOverlay(notice: notice, coordinator: broadcastCoordinator)
                    .zIndex(100_000)
            }
        }
        .task(id: broadcastCoordinator.chatMessages.compactMap { $0.tradeID?.rawValue }.sorted().joined(separator: ",")) {
            await broadcastCoordinator.hydrateBroadcastChatTradesIfNeeded()
        }
        .task(id: broadcastCoordinator.rosterParticipants.map(\.identity).joined(separator: ",")) {
            let rosterIds = broadcastCoordinator.rosterParticipants.map(\.identity)
            await broadcastCoordinator.chatProfileCache.hydrate(userIds: rosterIds)
        }
    }

    private var tabMemberCount: Int {
        let programIdentity = broadcastCoordinator.polledStatus.primaryMediaPublisherIdentity
        return broadcastCoordinator.rosterParticipants.filter { participant in
            participant.roleLabel != "Broadcaster"
                && BroadcastRosterPresentation.shouldListInRoster(
                    identity: participant.identity,
                    programPublisherIdentity: programIdentity
                )
        }.count
    }

    private var tabRaisedHandCount: Int {
        let programIdentity = broadcastCoordinator.polledStatus.primaryMediaPublisherIdentity
        let fromRoster = broadcastCoordinator.rosterParticipants.filter {
            $0.isHandRaised
                && BroadcastRosterPresentation.shouldListInRoster(
                    identity: $0.identity,
                    programPublisherIdentity: programIdentity
                )
        }
        let ids = broadcastCoordinator.broadcastRaisedHandIdentities
            .union(broadcastCoordinator.interactiveRaisedHandUserIds)
        let known = Set(fromRoster.map(\.identity))
        let extras = ids.subtracting(known).filter {
            BroadcastRosterPresentation.shouldListInRoster(
                identity: $0,
                programPublisherIdentity: programIdentity
            )
        }
        return fromRoster.count + extras.count
    }

    private var statusBannerMessage: String? {
        if let msg = controller.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !msg.isEmpty {
            return msg
        }
        if let err = broadcastCoordinator.lastError?.trimmingCharacters(in: .whitespacesAndNewlines), !err.isEmpty {
            return err
        }
        return nil
    }

    private var manageHeader: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            Button(action: dismissManagePreservingBroadcast) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(colors.primaryText)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.experiencePlain)
            .accessibilityLabel("Minimize")

            BroadcastDurationCountdownView(
                expiresAt: broadcastCoordinator.broadcastExpiresAt,
                style: .navigationTitle
            )

            Button(action: toggleCornerVideoPin) {
                Image(systemName: isHostVideoCornerPinned ? "pip.exit" : "pip.enter")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isHostVideoCornerPinned ? colors.accent : colors.primaryText)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.experiencePlain)
            .accessibilityLabel(isHostVideoCornerPinned ? "Expand video" : "Minimize video for chat")

            Button("End Stream") {
                showsEndStreamConfirmation = true
            }
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(colors.error)
            .disabled(controller.isBusy)
            .opacity(controller.isBusy ? ExperienceOpacity.disabled : ExperienceOpacity.opaque)
            .buttonStyle(.experiencePlain)
            .accessibilityIdentifier("tradeRooms.broadcast.endStream")
        }
        .padding(.horizontal, ExperienceSpacing.sm)
        .padding(.vertical, ExperienceSpacing.xs)
        .background(colors.navigationBackground.opacity(0.98))
        .contentShape(Rectangle())
        .simultaneousGesture(headerMinimizeDragGesture)
    }

    private func dismissManagePreservingBroadcast() {
        ExperienceHaptics.play(.selection)
        onClose()
    }

    private func toggleCornerVideoPin() {
        ExperienceHaptics.play(.selection)
        let animation: Animation? = reduceMotion ? nil : .snappy(duration: 0.28)
        withAnimation(animation) {
            isHostVideoCornerPinned.toggle()
            if isHostVideoCornerPinned {
                isTypingMiniPlayerDismissed = false
            }
        }
    }

    private func unpinnedCornerVideo() {
        ExperienceHaptics.play(.selection)
        let animation: Animation? = reduceMotion ? nil : .snappy(duration: 0.28)
        withAnimation(animation) {
            isHostVideoCornerPinned = false
            isTypingMiniPlayerDismissed = false
        }
    }

    private var cornerVideoDismissedPlaceholder: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func syncProgramVideoSurfaceForLayout(cornerVideo: Bool, fullscreen: Bool) {
        if fullscreen {
            broadcastCoordinator.adoptProgramVideoSurface(.sheetFullscreen)
        } else if cornerVideo {
            broadcastCoordinator.adoptProgramVideoSurface(
                isTypingMiniPlayerDismissed ? .cornerDismissedHold : .cornerChat
            )
        } else {
            broadcastCoordinator.adoptProgramVideoSurface(.inlineExpanded)
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
                dismissManagePreservingBroadcast()
            }
    }

    private var fullscreenPlayer: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            BroadcastStreamZoomableVideoView(
                track: broadcastCoordinator.videoTrackForExpandedViewer,
                trackRevision: broadcastCoordinator.programVideoTrackRevision,
                isFullscreen: true,
                onFirstFrame: { broadcastCoordinator.markProgramVideoFrameRendered() }
            )
            .id(broadcastCoordinator.programVideoRendererIdentity)
            .opacity(broadcastCoordinator.hasDisplayableProgramVideo ? 1 : 0)
            .ignoresSafeArea()

            if let placeholder = broadcastCoordinator.programVideoPlaceholder {
                BroadcastProgramVideoPlaceholderOverlay(presentation: placeholder)
                    .ignoresSafeArea()
            }

            VStack {
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
                .padding(ExperienceSpacing.md)
                Spacer()
                HStack {
                    Spacer()
                    RoomBroadcastStreamPlaybackMuteButton(coordinator: broadcastCoordinator)
                }
                .padding(ExperienceSpacing.md)
            }
        }
    }
}