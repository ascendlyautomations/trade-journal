import SwiftUI
import UIKit

struct TradeRoomInboxRowView: View {
    let item: TradeRoomInboxItem
    let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors
    @State private var logoImage: Image?

    var body: some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
            logo
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.xs) {
                    Text(item.room.name)
                        .experienceStyle(item.unreadCount > 0 ? .headline : .body, color: colors.primaryText)
                        .lineLimit(1)
                    if item.ownerIsVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundStyle(colors.accent)
                    }
                    if item.isMuted {
                        Text("Muted")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(colors.tertiaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(colors.fillSecondary, in: Capsule())
                    }
                    Spacer(minLength: 4)
                    if let timestamp = item.timestamp {
                        Text(MessagesInboxSupport.relativeTimestamp(timestamp))
                            .experienceStyle(.caption2, color: colors.tertiaryText)
                    }
                    if item.unreadCount > 0 {
                        Text(item.unreadCount > 99 ? "99+" : "\(item.unreadCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(colors.onAccent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(colors.accent, in: Capsule())
                    }
                }
                HStack(spacing: ExperienceSpacing.xs) {
                    Text(item.isPrivate ? "Private" : "Public")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(item.isPrivate ? colors.warning : colors.accent)
                    if let ownerName = item.ownerName, !ownerName.isEmpty {
                        Text("· \(ownerName)")
                            .experienceStyle(.caption, color: colors.secondaryText)
                            .lineLimit(1)
                    }
                    if let memberCount = item.room.memberCount {
                        Text("· \(ProfileDisplay.compactCount(memberCount)) members")
                            .experienceStyle(.caption, color: colors.secondaryText)
                            .lineLimit(1)
                    }
                }
                Text(item.preview)
                    .experienceStyle(
                        item.unreadCount > 0 ? .subheadline : .footnote,
                        color: item.unreadCount > 0 ? colors.primaryText : colors.secondaryText
                    )
                    .lineLimit(2)
            }
        }
        .padding(.vertical, ExperienceSpacing.xs)
        .contentShape(Rectangle())
        .task(id: item.room.image?.id) {
            await loadLogo()
        }
        .experienceAccessibility(
            label: "\(item.room.name). \(item.preview)",
            identifier: "messages.room.\(item.id.rawValue)"
        )
    }

    private var logo: some View {
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
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
    }

    private func loadLogo() async {
        guard let reference = item.room.image else {
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
