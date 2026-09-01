import SwiftUI
import UIKit

/// Premium Trade Room card for the dedicated Rooms home.
struct TradeRoomCardView: View {
    let item: TradeRoomInboxItem
    let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors
    @State private var logoImage: Image?

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            banner
            HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                logo
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.xs) {
                        Text(item.room.name)
                            .experienceStyle(
                                item.unreadCount > 0 ? .headline : .body,
                                color: colors.primaryText
                            )
                            .lineLimit(1)
                        if item.ownerIsVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundStyle(colors.accent)
                                .accessibilityLabel("Verified")
                        }
                        Spacer(minLength: 4)
                        if let timestamp = item.timestamp {
                            Text(MessagesInboxSupport.relativeTimestamp(timestamp))
                                .experienceStyle(.caption2, color: colors.tertiaryText)
                        }
                    }

                    HStack(spacing: ExperienceSpacing.xs) {
                        if let ownerName = item.ownerName, !ownerName.isEmpty {
                            Text(ownerName)
                                .experienceStyle(.caption, color: colors.secondaryText)
                                .lineLimit(1)
                        }
                        if let memberCount = item.room.memberCount {
                            if item.ownerName?.isEmpty == false {
                                Text("·")
                                    .experienceStyle(.caption2, color: colors.tertiaryText)
                            }
                            Text("\(ProfileDisplay.compactCount(memberCount)) members")
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

                    HStack(spacing: ExperienceSpacing.xs) {
                        badge(
                            title: item.isPrivate ? "Private" : "Public",
                            tint: item.isPrivate ? colors.warning : colors.accent
                        )
                        if item.isMuted {
                            badge(title: "Muted", tint: colors.tertiaryText)
                        }
                        Spacer(minLength: 0)
                        if item.unreadCount > 0 {
                            Text(item.unreadCount > 99 ? "99+" : "\(item.unreadCount)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(colors.onAccent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(colors.accent, in: Capsule())
                        }
                    }
                }
            }
        }
        .padding(ExperienceSpacing.sm)
        .background(
            colors.backgroundSecondary,
            in: RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
        )
        .contentShape(Rectangle())
        .task(id: item.room.image?.id) {
            await loadLogo()
        }
        .experienceAccessibility(
            label: "\(item.room.name). \(item.preview)",
            identifier: "tradeRooms.card.\(item.id.rawValue)"
        )
    }

    private var banner: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    colors.accent.opacity(0.35),
                    colors.fillSecondary.opacity(0.9),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if let logoImage {
                logoImage
                    .resizable()
                    .scaledToFill()
                    .opacity(0.22)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 72)
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
        .overlay(alignment: .topTrailing) {
            ExperienceIcon(icon: .rooms, size: .sm, color: colors.onAccent.opacity(0.85))
                .padding(ExperienceSpacing.xs)
        }
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

    private func badge(title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.14), in: Capsule())
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
}
