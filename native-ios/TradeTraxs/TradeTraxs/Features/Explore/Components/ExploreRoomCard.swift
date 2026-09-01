import SwiftUI
import UIKit

struct ExploreRoomCard: View {
    let room: ExploreRoomSuggestion
    let imagePipeline: any ImagePipeline
    let onOpen: () -> Void

    @Environment(\.themeColors) private var colors
    @State private var image: Image?

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                        .fill(colors.fillSecondary)
                        .frame(height: 72)
                    if let image {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous))
                    } else {
                        Image(systemName: "person.3.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(colors.accent)
                    }
                }

                Text(room.name)
                    .experienceStyle(.subheadline, color: colors.primaryText)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                if let memberCount = room.memberCount {
                    Text("\(ProfileDisplay.compactCount(memberCount)) members")
                        .experienceStyle(.caption2, color: colors.secondaryText)
                        .lineLimit(1)
                }
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
            ExploreRoomCard(room: room, imagePipeline: imagePipeline, onOpen: {})
        }
        .task(id: room.imageReference?.id) {
            await loadImage()
        }
        .accessibilityIdentifier("explore.room.\(room.id.rawValue)")
    }

    private func loadImage() async {
        guard let reference = room.imageReference else {
            image = nil
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
                image = Image(uiImage: ui)
            }
        } catch {
            image = nil
        }
    }
}
