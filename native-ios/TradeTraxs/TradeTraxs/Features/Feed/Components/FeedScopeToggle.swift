import SwiftUI

/// Compact Following / Global menu — same presentation pattern as profile trades sort.
struct FeedScopeToggle: View {
    @Binding var scope: FeedScope
    let onChange: (FeedScope) -> Void

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
            HStack(spacing: 4) {
                Text(title)
                    .experienceStyle(.subheadline, color: colors.primaryText)
                ExperienceIcon(icon: .chevronDown, size: .xs, color: colors.secondaryText)
            }
            .padding(.horizontal, ExperienceSpacing.sm)
            .frame(minHeight: 28)
            .background(colors.fillSecondary)
            .clipShape(Capsule())
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
