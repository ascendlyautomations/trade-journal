import SwiftUI

/// Joined-room hit during Trade Rooms search, same structure as ``ExploreTraderListRow``.
struct TradeRoomInboxSearchListRow: View {
    let item: TradeRoomInboxItem
    let imagePipeline: any ImagePipeline
    let onOpen: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.md) {
            Button(action: onOpen) {
                HStack(alignment: .center, spacing: ExperienceSpacing.md) {
                    TradeRoomCircularAvatar(
                        imageReference: item.room.image,
                        imagePipeline: imagePipeline,
                        diameter: 40,
                        placeholderIconColor: colors.secondaryText
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.room.name)
                            .experienceStyle(.subheadline, color: colors.primaryText)
                            .fontWeight(.semibold)
                            .lineLimit(1)

                        if let owner = item.ownerName?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !owner.isEmpty
                        {
                            Text(owner)
                                .experienceStyle(.caption, color: colors.secondaryText)
                                .lineLimit(1)
                        }

                        let preview = item.preview.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !preview.isEmpty {
                            Text(preview)
                                .experienceStyle(.caption2, color: colors.tertiaryText)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: ExperienceSpacing.sm)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.experiencePlain)

            Text("Joined")
                .font(.caption.weight(.semibold))
                .foregroundStyle(colors.primaryText)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Capsule().fill(colors.fillSecondary))
                .accessibilityAddTraits(.isStaticText)
        }
        .accessibilityIdentifier("tradeRooms.search.joined.\(item.id.rawValue)")
    }
}