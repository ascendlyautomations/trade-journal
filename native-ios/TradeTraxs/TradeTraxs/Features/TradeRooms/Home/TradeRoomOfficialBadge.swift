import SwiftUI

/// Compact Official indicator for TradeTraxs-managed global rooms.
struct TradeRoomOfficialBadge: View {
    var style: Style = .checkmark

    @Environment(\.themeColors) private var colors

    enum Style {
        case checkmark
        case label
    }

    var body: some View {
        switch style {
        case .checkmark:
            Image(systemName: "checkmark.seal.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(colors.accent)
                .accessibilityLabel("Official")
        case .label:
            Text("Official")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(colors.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(colors.accent.opacity(0.12), in: Capsule())
                .accessibilityLabel("Official Trade Room")
        }
    }
}
