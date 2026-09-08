import SwiftUI

/// Preset color keys for room member tags — maps to theme accents.
enum RoomMemberTagSupport {
    static let defaultColorKey = "accent"

    static let presetColorKeys: [(key: String, label: String)] = [
        ("accent", "Accent"),
        ("blue", "Blue"),
        ("green", "Green"),
        ("orange", "Orange"),
        ("purple", "Purple"),
        ("pink", "Pink"),
        ("teal", "Teal"),
        ("gray", "Gray"),
    ]

    static func color(for key: String, colors: SemanticColorPalette) -> Color {
        switch key {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "pink": return .pink
        case "teal": return .teal
        case "gray": return colors.tertiaryText
        default: return colors.accent
        }
    }
}

struct RoomMemberTagChipsView: View {
    let tags: [RoomMemberTag]
    var showsOwnerBadge: Bool = false
    var limit: Int = 4

    @Environment(\.themeColors) private var colors

    var body: some View {
        let visible = Array(tags.prefix(limit))
        let overflow = max(tags.count - visible.count, 0)
        HStack(spacing: ExperienceSpacing.xxs) {
            if showsOwnerBadge {
                tagCapsule(label: "Owner", color: colors.accent)
            }
            ForEach(visible) { tag in
                tagCapsule(
                    label: tag.name,
                    color: RoomMemberTagSupport.color(for: tag.colorKey, colors: colors)
                )
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(colors.tertiaryText)
            }
        }
    }

    private func tagCapsule(label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
            .lineLimit(1)
    }
}
