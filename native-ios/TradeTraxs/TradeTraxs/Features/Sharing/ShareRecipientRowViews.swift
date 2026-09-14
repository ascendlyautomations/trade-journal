import SwiftUI
import UIKit

/// DM destination row — profile avatar + name / @username + optional selection checkmark.
struct ShareRecipientConversationRow: View {
    let conversation: Conversation
    let imagePipeline: any ImagePipeline
    var isSelected: Bool = false

    @Environment(\.themeColors) private var colors
    @State private var avatarImage: Image?

    var body: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            ExperienceAvatar(
                initials: ProfileDisplay.initials(
                    displayName: conversation.title ?? "",
                    username: conversation.peerUsername ?? "?"
                ),
                image: avatarImage,
                size: 44
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.title ?? "Conversation")
                    .experienceStyle(.headline, color: colors.primaryText)
                    .lineLimit(1)
                if let username = conversation.peerUsername?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !username.isEmpty
                {
                    Text("@\(username)")
                        .experienceStyle(.caption, color: colors.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            selectionMark
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .task(id: conversation.avatar?.id) {
            await loadAvatar()
        }
    }

    @ViewBuilder
    private var selectionMark: some View {
        ZStack {
            Circle()
                .stroke(isSelected ? colors.accent : colors.border, lineWidth: isSelected ? 0 : 1.5)
                .frame(width: 24, height: 24)
            if isSelected {
                Circle()
                    .fill(colors.accent)
                    .frame(width: 24, height: 24)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(colors.onAccent)
            }
        }
        .accessibilityHidden(true)
    }

    private func loadAvatar() async {
        guard let reference = conversation.avatar else {
            avatarImage = nil
            return
        }
        do {
            let data = try await imagePipeline.data(
                for: ImageRequest(
                    reference: reference,
                    purpose: .profileAvatar,
                    maxPixelSize: 128
                )
            )
            if let ui = UIImage(data: data) {
                avatarImage = Image(uiImage: ui)
            }
        } catch {
            avatarImage = nil
        }
    }
}

/// Trade Room destination row — room image + name / "Trade Room" + optional selection checkmark.
struct ShareRecipientTradeRoomRow: View {
    let room: TradeRoom
    let imagePipeline: any ImagePipeline
    var isSelected: Bool = false

    @Environment(\.themeColors) private var colors
    @State private var logoImage: Image?

    var body: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            roomAvatar
            VStack(alignment: .leading, spacing: 2) {
                Text(room.name)
                    .experienceStyle(.headline, color: colors.primaryText)
                    .lineLimit(1)
                Text("Trade Room")
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            selectionMark
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .task(id: room.image?.id) {
            await loadLogo()
        }
    }

    @ViewBuilder
    private var selectionMark: some View {
        ZStack {
            Circle()
                .stroke(isSelected ? colors.accent : colors.border, lineWidth: isSelected ? 0 : 1.5)
                .frame(width: 24, height: 24)
            if isSelected {
                Circle()
                    .fill(colors.accent)
                    .frame(width: 24, height: 24)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(colors.onAccent)
            }
        }
        .accessibilityHidden(true)
    }

    private var roomAvatar: some View {
        Group {
            if let logoImage {
                logoImage
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    colors.fillSecondary
                    ExperienceIcon(icon: .rooms, size: .md, color: colors.accent)
                }
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
        .overlay {
            Circle().stroke(colors.border, lineWidth: ExperienceBorder.hairline)
        }
    }

    private func loadLogo() async {
        guard let reference = room.image else {
            logoImage = nil
            return
        }
        do {
            let data = try await imagePipeline.data(
                for: ImageRequest(
                    reference: reference,
                    purpose: .profileAvatar,
                    maxPixelSize: 128
                )
            )
            if let ui = UIImage(data: data) {
                logoImage = Image(uiImage: ui)
            }
        } catch {
            logoImage = nil
        }
    }
}
