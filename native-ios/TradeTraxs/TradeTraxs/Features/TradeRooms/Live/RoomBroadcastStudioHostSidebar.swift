import SwiftUI

enum RoomBroadcastStudioHostTab: String, CaseIterable, Identifiable {
    case chat = "Chat"
    case members = "Members"
    case hands = "Hands"

    var id: String { rawValue }
}

struct RoomBroadcastStudioHostTabBar: View {
    @Binding var selectedTab: RoomBroadcastStudioHostTab
    let memberCount: Int
    let raisedHandCount: Int
    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: 0) {
            ForEach(RoomBroadcastStudioHostTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(label(for: tab))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(selectedTab == tab ? colors.primaryText : colors.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            selectedTab == tab
                                ? colors.fillSecondary.opacity(0.85)
                                : Color.clear
                        )
                }
                .buttonStyle(.experiencePlain)
            }
        }
        .background(colors.navigationBackground.opacity(0.98))
    }

    private func label(for tab: RoomBroadcastStudioHostTab) -> String {
        switch tab {
        case .chat:
            return tab.rawValue
        case .members:
            return memberCount > 0 ? "Members (\(memberCount))" : tab.rawValue
        case .hands:
            return raisedHandCount > 0 ? "Hands (\(raisedHandCount))" : tab.rawValue
        }
    }
}

/// Host sidebar tabs: chat, members, raised hands (mirrors web host studio).
struct RoomBroadcastStudioHostSidebar: View {
    let roomID: RoomID
    var isHostBroadcaster: Bool = false
    var embedsTabBar: Bool = true
    let broadcasterUserId: String?
    @Bindable var coordinator: RoomBroadcastCoordinator
    let imagePipeline: any ImagePipeline
    let userId: String?
    let displayName: String
    @Binding var chatDraft: String
    @Binding var selectedTab: RoomBroadcastStudioHostTab
    /// Matches viewer livestream: Send key, keyboard + compact video, scroll-to-latest on focus.
    var useViewerKeyboardChrome: Bool = false
    var composerFocusedBinding: Binding<Bool>? = nil
    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(spacing: 0) {
            if let modErr = coordinator.broadcastModerationError, !modErr.isEmpty {
                HStack {
                    Text(modErr)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(colors.error)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Button("Dismiss") {
                        coordinator.acknowledgeBroadcastModerationError()
                    }
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                }
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.vertical, ExperienceSpacing.xxs)
                .background(colors.error.opacity(0.08))
            }
            if embedsTabBar {
                RoomBroadcastStudioHostTabBar(
                    selectedTab: $selectedTab,
                    memberCount: memberRows.count,
                    raisedHandCount: raisedHandRows.count
                )
            }
            Group {
                switch selectedTab {
                case .chat:
                    RoomBroadcastStudioChatPane(
                        coordinator: coordinator,
                        imagePipeline: imagePipeline,
                        userId: userId,
                        displayName: displayName,
                        chatDraft: $chatDraft,
                        useViewerKeyboardChrome: useViewerKeyboardChrome,
                        composerFocusedBinding: composerFocusedBinding
                    )
                case .members:
                    membersPane
                case .hands:
                    handsPane
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(colors.primaryBackground)
    }

    private var membersPane: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                Text("\(coordinator.localViewerCount) watching")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(colors.secondaryText)
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.top, ExperienceSpacing.sm)

                if memberRows.isEmpty {
                    Text("Waiting for viewers to join…")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(colors.secondaryText)
                        .padding(.horizontal, ExperienceSpacing.md)
                } else {
                    ForEach(memberRows) { participant in
                        participantRow(participant, surface: .participant)
                            .padding(.horizontal, ExperienceSpacing.md)
                    }
                }
            }
            .padding(.bottom, ExperienceSpacing.md)
        }
    }

    private var handsPane: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                if raisedHandRows.isEmpty {
                    Text("No raised hands yet.")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(colors.secondaryText)
                        .padding(.horizontal, ExperienceSpacing.md)
                        .padding(.top, ExperienceSpacing.sm)
                } else {
                    ForEach(raisedHandRows, id: \.identity) { participant in
                        participantRow(participant, surface: .raisedHand)
                            .padding(.horizontal, ExperienceSpacing.md)
                    }
                }
            }
            .padding(.vertical, ExperienceSpacing.sm)
        }
    }

    private var programPublisherIdentity: String? {
        coordinator.polledStatus.primaryMediaPublisherIdentity
    }

    private var memberRows: [BroadcastRosterParticipant] {
        coordinator.rosterParticipants.filter { participant in
            participant.roleLabel != "Broadcaster"
                && BroadcastRosterPresentation.shouldListInRoster(
                    identity: participant.identity,
                    programPublisherIdentity: programPublisherIdentity
                )
        }
    }

    private var raisedHandRows: [BroadcastRosterParticipant] {
        let fromRoster = coordinator.rosterParticipants.filter { participant in
            participant.isHandRaised
                && BroadcastRosterPresentation.shouldListInRoster(
                    identity: participant.identity,
                    programPublisherIdentity: programPublisherIdentity
                )
        }
        let ids = coordinator.broadcastRaisedHandIdentities
            .union(coordinator.interactiveRaisedHandUserIds)
        let known = Set(fromRoster.map(\.identity))
        let extras = ids.subtracting(known).sorted().compactMap { identity -> BroadcastRosterParticipant? in
            guard isModerationTargetIdentity(identity) else { return nil }
            let profile = coordinator.chatProfileCache.profile(forUserId: identity)
            return BroadcastRosterParticipant(
                identity: identity,
                displayName: BroadcastRosterPresentation.memberRowLabel(
                    profile: profile,
                    liveKitFallbackName: "",
                    userId: identity
                ),
                roleLabel: "Viewer",
                isHandRaised: true,
                isLocal: false
            )
        }
        return fromRoster + extras
    }

    private func participantRow(
        _ participant: BroadcastRosterParticipant,
        surface: RoomBroadcastHostModerationControls.Surface
    ) -> some View {
        let profile = coordinator.chatProfileCache.profile(forUserId: participant.identity)
        let rowLabel = BroadcastRosterPresentation.memberRowLabel(
            profile: profile,
            liveKitFallbackName: participant.displayName,
            userId: participant.identity
        )
        return HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
            RoomBroadcastProfileIdentityControl(
                userId: participant.identity,
                displayName: profile?.displayName ?? rowLabel,
                username: profile?.username ?? rowLabel,
                avatarDiameter: 36,
                coordinator: coordinator,
                imagePipeline: imagePipeline,
                profile: profile
            )
            .layoutPriority(1)
            RoomBroadcastParticipantStatusBadges(
                userId: participant.identity,
                coordinator: coordinator
            )
            .layoutPriority(0)
            if surface == .raisedHand {
                Image(systemName: "hand.raised.fill")
                    .font(.caption)
                    .foregroundStyle(colors.accent)
            }
            if let role = participant.rosterRoleDisplay {
                Text(role)
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .lineLimit(1)
            }
            if isHostBroadcaster, isModerationTarget(participant) {
                RoomBroadcastHostModerationControls(
                    roomID: roomID,
                    targetUserId: participant.identity,
                    targetDisplayName: BroadcastRosterPresentation.moderationDisplayName(
                        profile: profile,
                        participant: participant
                    ),
                    surface: surface,
                    coordinator: coordinator,
                    hostUserId: userId,
                    hostDisplayName: displayName
                )
                .layoutPriority(0)
            }
        }
    }

    private func isModerationTarget(_ participant: BroadcastRosterParticipant) -> Bool {
        guard isModerationTargetIdentity(participant.identity) else { return false }
        if participant.roleLabel == "Broadcaster" { return false }
        if let broadcasterUserId, participant.identity == broadcasterUserId { return false }
        return true
    }

    private func isModerationTargetIdentity(_ identity: String) -> Bool {
        BroadcastRosterPresentation.shouldListInRoster(
            identity: identity,
            programPublisherIdentity: programPublisherIdentity
        )
    }
}
