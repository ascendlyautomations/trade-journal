import SwiftUI

/// Compact Following / Global menu for the Feed navigation bar (leading).
struct FeedScopeToggle: View {
    @Binding var scope: FeedScope
    var onChange: (FeedScope) -> Void = { _ in }

    @Environment(\.themeColors) private var colors

    var body: some View {
        Menu {
            Button {
                select(.following)
            } label: {
                if scope == .following {
                    Label("Following", systemImage: "checkmark")
                } else {
                    Text("Following")
                }
            }
            .accessibilityIdentifier("feed.scope.following")

            Button {
                select(.global)
            } label: {
                if scope == .global {
                    Label("Global", systemImage: "checkmark")
                } else {
                    Text("Global")
                }
            }
            .accessibilityIdentifier("feed.scope.global")
        } label: {
            HStack(spacing: 3) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(colors.primaryText)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(colors.secondaryText)
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Feed scope")
        .accessibilityValue(title)
        .accessibilityIdentifier("feed.scope")
    }

    private var title: String {
        switch scope {
        case .following: return "Following"
        case .global: return "Global"
        }
    }

    private func select(_ value: FeedScope) {
        guard scope != value else { return }
        ExperienceHaptics.play(.selection)
        scope = value
        onChange(value)
    }
}
