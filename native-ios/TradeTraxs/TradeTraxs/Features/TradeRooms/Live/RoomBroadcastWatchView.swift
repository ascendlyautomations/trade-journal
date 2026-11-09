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
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            streamHeader
            videoSection
            if let error = coordinator.lastError {
                Text(error)
                    .experienceStyle(.caption, color: colors.error)
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.vertical, ExperienceSpacing.xxs)
            }
            chatList
            composerBar
            streamToolbar
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
                Text(roomTitle)
                    .experienceStyle(.subheadline, color: colors.primaryText)
                    .lineLimit(1)
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
    }

    private var videoSection: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black
            BroadcastStreamZoomableVideoView(
                track: coordinator.videoTrackForDisplay,
                isFullscreen: false
            )
            .id(coordinator.programVideoTrackRevision)
            HStack(spacing: ExperienceSpacing.xs) {
                if coordinator.isStreamPlaybackMuted {
                    Image(systemName: "speaker.slash.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                }
                Button {
                    isFullscreen = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                }
                .buttonStyle(.experiencePlain)
                .accessibilityLabel("Fullscreen")
            }
            .padding(ExperienceSpacing.sm)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var chatList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                    ForEach(coordinator.chatMessages) { msg in
                        chatRow(msg)
                            .id(msg.id)
                    }
                }
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.vertical, ExperienceSpacing.sm)
            }
            .frame(maxHeight: .infinity)
            .onChange(of: coordinator.chatMessages.count) { _, _ in
                if let last = coordinator.chatMessages.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var composerBar: some View {
        HStack(alignment: .bottom, spacing: ExperienceSpacing.xxs) {
            TextField("Message…", text: $chatDraft, axis: .vertical)
                .lineLimit(1 ... 4)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.sentences)
                .focused($composerFocused)
                .disabled(userId == nil)
                .padding(.horizontal, ExperienceSpacing.sm)
                .padding(.vertical, ExperienceSpacing.xs)
                .frame(
                    minHeight: ExperienceAccessibility.minTouchTarget,
                    alignment: .leading
                )
                .background(
                    colors.fillSecondary,
                    in: RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
                )

            if canSendChat {
                Button(action: sendChat) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(colors.accent)
                        .experienceTouchTarget()
                }
                .buttonStyle(.experiencePlain)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal, ExperienceSpacing.xs)
        .padding(.vertical, ExperienceSpacing.xs)
        .background(colors.navigationBackground.opacity(0.96))
    }

    private var canSendChat: Bool {
        guard userId != nil else { return false }
        return !chatDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

            toolbarIcon(
                systemName: coordinator.isStreamPlaybackMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                label: coordinator.isStreamPlaybackMuted ? "Unmute stream" : "Mute stream",
                tint: colors.primaryText
            ) {
                Task { await coordinator.toggleStreamPlaybackMute() }
            }

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
                track: coordinator.videoTrackForDisplay,
                isFullscreen: true
            )
            .id(coordinator.programVideoTrackRevision)
            .ignoresSafeArea()

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
                    fullscreenControl(
                        systemName: coordinator.isStreamPlaybackMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
                    ) {
                        Task { await coordinator.toggleStreamPlaybackMute() }
                    }
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

    @ViewBuilder
    private func chatRow(_ msg: BroadcastChatMessageItem) -> some View {
        let profile = coordinator.chatProfileCache.profile(forUserId: msg.userId)
        let name = profile?.displayName ?? msg.displayName
        let username = profile?.username ?? msg.displayName
        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
            if let profile {
                ExploreProfileAvatarView(
                    profile: profile,
                    imagePipeline: imagePipeline,
                    diameter: 32
                )
            } else {
                ExperienceAvatar(
                    initials: ProfileDisplay.initials(displayName: name, username: username),
                    size: 32
                )
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(username.isEmpty ? name : username)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(colors.primaryText)
                    Text(relativeTime(msg.sentAt))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(colors.tertiaryText)
                }
                Text(msg.text)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(colors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private func sendChat() {
        guard let userId else { return }
        let draft = chatDraft
        chatDraft = ""
        Task {
            await coordinator.sendChat(
                userId: userId,
                displayName: displayName,
                avatarUrl: nil,
                text: draft
            )
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
