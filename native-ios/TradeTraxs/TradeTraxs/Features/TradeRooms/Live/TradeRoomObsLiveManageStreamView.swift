import SwiftUI

/// OBS live host UI — viewer-style video + tabbed chat / members / hands.
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
    @State private var chatDraft = ""
    @State private var selectedTab: RoomBroadcastStudioHostTab = .chat
    @State private var isFullscreen = false
    @State private var showsEndStreamConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            manageHeader
            RoomBroadcastStudioVideoSection(
                coordinator: broadcastCoordinator,
                isFullscreen: $isFullscreen
            )
            if let banner = statusBannerMessage {
                Text(banner)
                    .experienceStyle(.caption, color: colors.error)
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.vertical, ExperienceSpacing.xxs)
            }
            RoomBroadcastStudioHostSidebar(
                roomID: roomID,
                isHostBroadcaster: true,
                broadcasterUserId: broadcastCoordinator.polledStatus.broadcasterUserId,
                coordinator: broadcastCoordinator,
                imagePipeline: imagePipeline,
                userId: chatUserId,
                displayName: chatDisplayName,
                chatDraft: $chatDraft,
                selectedTab: $selectedTab
            )
        }
        .background(colors.primaryBackground)
        .fullScreenCover(isPresented: $isFullscreen) {
            fullscreenPlayer
        }
        .alert("Are you sure you want to end the stream?", isPresented: $showsEndStreamConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("End Stream", role: .destructive) {
                Task {
                    await controller.endStream(roomID: roomID)
                    onClose()
                }
            }
        }
        .onChange(of: broadcastCoordinator.streamEndedNotice?.id) { _, noticeID in
            if noticeID != nil {
                isFullscreen = false
                onClose()
            }
        }
        .overlay {
            if let notice = broadcastCoordinator.speakInviteNotice {
                BroadcastSpeakInviteOverlay(notice: notice, coordinator: broadcastCoordinator)
                    .zIndex(100_000)
            }
        }
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
            Button(action: onClose) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(colors.primaryText)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.experiencePlain)
            .accessibilityLabel("Close")

            Text("Manage Stream")
                .experienceStyle(.subheadline, color: colors.primaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            Button("End Stream") {
                showsEndStreamConfirmation = true
            }
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(colors.error)
            .disabled(controller.isBusy)
            .accessibilityIdentifier("tradeRooms.broadcast.endStream")
        }
        .padding(.horizontal, ExperienceSpacing.sm)
        .padding(.vertical, ExperienceSpacing.xs)
        .background(colors.navigationBackground.opacity(0.98))
    }

    private var fullscreenPlayer: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            BroadcastStreamZoomableVideoView(
                track: broadcastCoordinator.videoTrackForDisplay,
                isFullscreen: true
            )
            .id(broadcastCoordinator.programVideoTrackRevision)
            .ignoresSafeArea()

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
