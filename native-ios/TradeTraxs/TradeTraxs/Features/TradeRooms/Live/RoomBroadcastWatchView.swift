import SwiftUI

struct RoomBroadcastWatchView: View {
    let roomID: RoomID
    let roomTitle: String
    let userId: String?
    let displayName: String
    @Bindable var coordinator: RoomBroadcastCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors
    @State private var chatDraft = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack {
                    Color.black
                    LiveKitBroadcastVideoView(track: coordinator.videoTrackForDisplay)
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: .infinity)

                streamVoiceControls

                if let error = coordinator.lastError {
                    Text(error)
                        .experienceStyle(.caption, color: colors.error)
                        .padding(.horizontal, ExperienceSpacing.md)
                        .padding(.top, ExperienceSpacing.xs)
                }

                chatSection
            }
            .background(colors.primaryBackground)
            .navigationTitle("Live")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Minimize") {
                        coordinator.minimizeViewer()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Leave Stream", role: .destructive) {
                        Task {
                            await coordinator.leaveWatch()
                            dismiss()
                        }
                    }
                }
            }
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
        }
    }

    @ViewBuilder
    private var streamVoiceControls: some View {
        if coordinator.isOpenVoiceStream {
            HStack(spacing: ExperienceSpacing.sm) {
                if coordinator.isInConversation {
                    ExperienceButton(
                        title: coordinator.isMicrophoneEnabledInStream ? "Mute mic" : "Unmute mic",
                        kind: .secondary
                    ) {
                        Task { await coordinator.toggleStreamMicrophone() }
                    }
                    ExperienceButton(title: "Leave conversation", kind: .secondary) {
                        Task { await coordinator.leaveConversation() }
                    }
                } else {
                    ExperienceButton(title: "Join Conversation", kind: .primary) {
                        Task { await coordinator.joinConversation() }
                    }
                }
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.top, ExperienceSpacing.sm)
        }
    }

    private var chatSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text("Live chat")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(colors.secondaryText)
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.top, ExperienceSpacing.sm)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                    ForEach(coordinator.chatMessages) { msg in
                        chatRow(msg)
                    }
                }
                .padding(.horizontal, ExperienceSpacing.md)
            }
            .frame(maxHeight: 220)

            HStack(spacing: ExperienceSpacing.xs) {
                TextField("Message…", text: $chatDraft)
                    .textFieldStyle(.roundedBorder)
                    .disabled(userId == nil)
                Button("Send") {
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
                .disabled(userId == nil || chatDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.bottom, ExperienceSpacing.sm)
        }
    }

    @ViewBuilder
    private func chatRow(_ msg: BroadcastChatMessageItem) -> some View {
        let profile = coordinator.chatProfileCache.profile(forUserId: msg.userId)
        let name = profile?.displayName ?? msg.displayName
        HStack(alignment: .top, spacing: ExperienceSpacing.xs) {
            ExperienceAvatar(
                initials: ProfileDisplay.initials(
                    displayName: name,
                    username: profile?.username ?? ""
                ),
                image: nil,
                size: 28
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                Text(msg.text)
                    .font(.system(.subheadline, design: .rounded))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
