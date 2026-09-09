import SwiftUI
import UIKit

struct ProfilePinnedSectionView: View {
    let items: [ProfilePinnedItem]
    let isOwner: Bool
    let imagePipeline: any ImagePipeline
    let onOpen: (ProfilePinnedItem) -> Void
    let onManage: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack {
                Text("Pinned")
                    .experienceStyle(.headline, color: colors.primaryText)
                Spacer(minLength: 0)
                if isOwner {
                    Button("Manage", action: onManage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(colors.accent)
                }
            }

            HStack(alignment: .top, spacing: ExperienceSpacing.xs) {
                ForEach(items.sorted(by: { $0.position < $1.position })) { item in
                    ProfilePinnedCardView(
                        item: item,
                        imagePipeline: imagePipeline,
                        onOpen: { onOpen(item) }
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityIdentifier("profile.pinned.section")
    }
}

struct ProfilePinnedCardView: View {
    let item: ProfilePinnedItem
    let imagePipeline: any ImagePipeline
    let onOpen: () -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme
    @State private var image: Image?

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.preview.kindLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(colors.accent)
                    .lineLimit(1)

                Group {
                    if let image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else if item.preview.imageReference != nil {
                        colors.fillSecondary
                    } else {
                        textPreview
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 72)
                .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous))

                Text(item.preview.title)
                    .experienceStyle(.caption, color: colors.primaryText)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let subtitle = item.preview.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !subtitle.isEmpty
                {
                    Text(subtitle)
                        .experienceStyle(.caption2, color: colors.secondaryText)
                        .lineLimit(1)
                } else if let value = item.preview.valueText?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !value.isEmpty
                {
                    Text(value)
                        .experienceStyle(.caption2, color: theme.metricColor(for: 1))
                        .lineLimit(1)
                }
            }
            .padding(ExperienceSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                    .fill(colors.surfacePrimary)
            )
        }
        .buttonStyle(.plain)
        .task(id: item.preview.imageURL) {
            await loadImage()
        }
        .accessibilityIdentifier("profile.pinned.card.\(item.id)")
    }

    @ViewBuilder
    private var textPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let value = item.preview.valueText, !value.isEmpty {
                Text(value)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(theme.metricColor(for: 1))
                    .lineLimit(1)
            }
            if let body = item.preview.body?.trimmingCharacters(in: .whitespacesAndNewlines),
               !body.isEmpty
            {
                Text(body)
                    .experienceStyle(.caption2, color: colors.secondaryText)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(ExperienceSpacing.xxs)
        .background(colors.fillSecondary)
    }

    private func loadImage() async {
        guard let reference = item.preview.imageReference else {
            image = nil
            return
        }
        do {
            let data = try await imagePipeline.data(
                for: ImageRequest(
                    reference: reference,
                    purpose: .postImage,
                    maxPixelSize: 240
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
