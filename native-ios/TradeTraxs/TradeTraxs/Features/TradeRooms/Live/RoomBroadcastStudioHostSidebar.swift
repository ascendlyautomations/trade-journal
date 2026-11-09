import SwiftUI

enum RoomBroadcastStudioHostTab: String, CaseIterable, Identifiable {
    case chat = "Chat"
    case members = "Members"
    case hands = "Hands Raised"

    var id: String { rawValue }
}

/// Host sidebar tabs: chat, members, raised hands (mirrors web host studio).
struct RoomBroadcastStudioHostSidebar: View {
    let roomID: RoomID
    var isHostBroadcaster: Bool = false
    let broadcasterUserId: String?
    @Bindable var coordinator: RoomBroadcastCoordinator
    let imagePipeline: any ImagePipeline
    let userId: String?
    let displayName: String
    @Binding var chatDraft: String
    @Binding var selectedTab: RoomBroadcastStudioHostTab
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
            tabBar
            Group {
                switch selectedTab {
                case .chat:
                    RoomBroadcastStudioChatPane(
                        coordinator: coordinator,
                        imagePipeline: imagePipeline,
                        userId: userId,
                        displayName: displayName,
                        chatDraft: $chatDraft
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

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(RoomBroadcastStudioHostTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tabLabel(tab))
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

    private func tabLabel(_ tab: RoomBroadcastStudioHostTab) -> String {
        switch tab {
        case .chat:
            return tab.rawValue
        case .members:
            let count = memberRows.count
            return count > 0 ? "Members (\(count))" : tab.rawValue
        case .hands:
            let count = raisedHandRows.count
            return count > 0 ? "Hands (\(count))" : "Hands Raised"
        }
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

    private var memberRows: [BroadcastRosterParticipant] {
        coordinator.rosterParticipants.filter { participant in
            participant.roleLabel != "Broadcaster"
        }
    }

    private var raisedHandRows: [BroadcastRosterParticipant] {
        let fromRoster = coordinator.rosterParticipants.filter(\.isHandRaised)
        let ids = coordinator.broadcastRaisedHandIdentities
            .union(coordinator.interactiveRaisedHandUserIds)
        let known = Set(fromRoster.map(\.identity))
        let extras = ids.subtracting(known).sorted().compactMap { identity -> BroadcastRosterParticipant? in
            guard isModerationTargetIdentity(identity) else { return nil }
            return BroadcastRosterParticipant(
                identity: identity,
                displayName: coordinator.chatProfileCache.profile(forUserId: identity)?.displayName
                    ?? identity,
                roleLabel: "Viewer",
                isHandRaised: true,
                isLocal: false
            )
        }
        return fromRoster + extras
    }

    @ViewBuilder
    private func participantRow(
        _ participant: BroadcastRosterParticipant,
        surface: RoomBroadcastHostModerationControls.Surface
    ) -> some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
            if let profile = coordinator.chatProfileCache.profile(forUserId: participant.identity) {
                ExploreProfileAvatarView(
                    profile: profile,
                    imagePipeline: imagePipeline,
                    diameter: 36
                )
            } else {
                ExperienceAvatar(
                    initials: ProfileDisplay.initials(
                        displayName: participant.displayName,
                        username: participant.identity
                    ),
                    size: 36
                )
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(participant.displayName)
                    .experienceStyle(.body, color: colors.primaryText)
                HStack(spacing: 6) {
                    Text(participant.roleLabel + (participant.isLocal ? " · you" : ""))
                        .experienceStyle(.caption, color: colors.secondaryText)
                    RoomBroadcastParticipantStatusBadges(
                        userId: participant.identity,
                        coordinator: coordinator
                    )
                }
            }
            Spacer(minLength: 0)
            if surface == .raisedHand {
                Image(systemName: "hand.raised.fill")
                    .font(.caption)
                    .foregroundStyle(colors.accent)
            }
            if isHostBroadcaster, isModerationTarget(participant) {
                RoomBroadcastHostModerationControls(
                    roomID: roomID,
                    targetUserId: participant.identity,
                    targetDisplayName: participant.displayName,
                    surface: surface,
                    coordinator: coordinator,
                    hostUserId: userId,
                    hostDisplayName: displayName
                )
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
        ProfileIDQueryPolicy.isQueryable(ProfileID(identity))
    }
}
