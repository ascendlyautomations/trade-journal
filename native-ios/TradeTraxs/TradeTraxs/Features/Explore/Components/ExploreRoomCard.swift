import SwiftUI

struct ExploreRoomCard: View {
    let room: ExploreRoomSuggestion
    let onOpen: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                        .fill(colors.fillSecondary)
                        .frame(height: 72)
                    Image(systemName: "person.3.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(colors.accent)
                }

                Text(room.name)
                    .experienceStyle(.subheadline, color: colors.primaryText)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text("\(ProfileDisplay.compactCount(room.memberCount)) members")
                    .experienceStyle(.caption2, color: colors.secondaryText)
                    .lineLimit(1)
                if let description = room.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !description.isEmpty
                {
                    Text(description)
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                        .lineLimit(2)
                }
            }
            .padding(ExperienceSpacing.sm)
            .frame(width: 168, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                    .fill(colors.surfacePrimary)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: onOpen) {
                Label("Open", systemImage: "person.3")
            }
        } preview: {
            ExploreRoomCard(room: room, onOpen: {})
        }
        .accessibilityIdentifier("explore.room.\(room.id.rawValue)")
    }
}
