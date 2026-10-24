import SwiftUI
import UIKit

/// Web `FeedRoomShareCard` — room snapshot on a profile post, with Join Room / Open Room.
struct FeedRoomShareCard: View {
    let share: RoomShareAttachment

    @Environment(\.themeColors) private var colors
    @Environment(\.appEnvironment) private var appEnvironment

    @State private var memberCount: Int?
    @State private var isMember = false
    @State private var isBusy = false
    @State private var logoImage: Image?
    @State private var statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                logo
                VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                    Text(share.name)
                        .experienceStyle(.headline, color: colors.primaryText)
                        .lineLimit(1)
                    Text(memberLabel)
                        .experienceStyle(.caption, color: colors.tertiaryText)
                    if let description = share.description, !description.isEmpty {
                        Text(description)
                            .experienceStyle(.subheadline, color: colors.secondaryText)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task { await performAction() }
            } label: {
                Group {
                    if isBusy {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(actionTitle)
                            .experienceStyle(.subheadline, color: colors.primaryText)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, ExperienceSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                        .fill(colors.profit.opacity(0.22))
                )
                .experienceControlHitTarget()
            }
            .buttonStyle(.experiencePlain)
            .disabled(isBusy)
            .accessibilityIdentifier("feed.roomShare.action")

            if let statusMessage, !statusMessage.isEmpty {
                Text(statusMessage)
                    .experienceStyle(.caption, color: colors.loss)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
                .fill(colors.fillSecondary)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
                .stroke(colors.border.opacity(ExperienceOpacity.subtle), lineWidth: ExperienceBorder.hairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feed.roomShare.card")
        .task(id: share.roomID) {
            await loadRoomState()
        }
        .task(id: share.logoURL) {
            await loadLogo()
        }
    }

    private var actionTitle: String {
        if isBusy { return isMember ? "Opening…" : "Joining…" }
        return isMember ? "Open Room" : "Join Room"
    }

    private var memberLabel: String {
        guard let memberCount else { return "Loading members…" }
        if memberCount == 1 { return "1 member" }
        return "\(ProfileDisplay.compactCount(memberCount)) members"
    }

    private var logo: some View {
        Group {
            if let logoImage {
                logoImage.resizable().scaledToFill()
            } else {
                ZStack {
                    colors.fillPrimary
                    ExperienceIcon(icon: .rooms, size: .sm, color: colors.accent)
                }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private func loadRoomState() async {
        let inbox = MessagesInboxStore.shared
        if let listed = inbox.rooms.first(where: { $0.id == share.roomID }) {
            isMember = true
            if memberCount == nil {
                memberCount = listed.memberCount
            }
        }

        let rooms = appEnvironment.data.rooms
        if let counts = try? await rooms.activeMemberCounts(for: [share.roomID]) {
            memberCount = counts[share.roomID] ?? memberCount ?? 0
        } else if memberCount == nil {
            memberCount = 0
        }

        guard let userID = await appEnvironment.data.session.currentUserID else { return }
        let viewerID = ProfileID(userID.rawValue)
        if (try? await rooms.membership(roomID: share.roomID, profileID: viewerID)) != nil {
            isMember = true
        }
    }

    private func loadLogo() async {
        guard let raw = share.logoURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            logoImage = nil
            return
        }
        let reference = MediaReference(id: raw, kind: .image, altText: nil)
        if let bundled = DemoExploreBundledAvatar.uiImage(for: reference) {
            logoImage = Image(uiImage: bundled)
            return
        }
        do {
            let data = try await appEnvironment.data.imagePipeline.data(
                for: ImageRequest(
                    reference: reference,
                    purpose: .profileAvatar,
                    maxPixelSize: 160
                )
            )
            if let ui = UIImage(data: data) {
                logoImage = Image(uiImage: ui)
            }
        } catch {
            logoImage = nil
        }
    }

    private func performAction() async {
        guard !isBusy else { return }
        statusMessage = nil

        if !ExploreModeSupport.canJoinRooms {
            statusMessage = "Create an account to join this room."
            return
        }

        guard let userID = await appEnvironment.data.session.currentUserID else {
            statusMessage = "Sign in to join this room."
            return
        }
        let viewerID = ProfileID(userID.rawValue)

        if isMember {
            appEnvironment.navigation.coordinator.pushRoom(share.roomID)
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            _ = try await appEnvironment.data.rooms.join(roomID: share.roomID, profileID: viewerID)
            isMember = true
            if let current = memberCount {
                memberCount = current + 1
            }
            SessionMemberRoomsStore.shared.invalidate(viewerID: viewerID)
            if let room = try? await appEnvironment.data.rooms.room(id: share.roomID) {
                GettingStartedRefreshCenter.noteJoinedOtherTradeRoom(from: room, viewer: viewerID)
            }
            ExperienceHaptics.play(.success)
            appEnvironment.navigation.coordinator.pushRoom(share.roomID)
        } catch {
            statusMessage = ProfileSectionSupport.message(for: error)
            ExperienceHaptics.play(.warning)
        }
    }
}
