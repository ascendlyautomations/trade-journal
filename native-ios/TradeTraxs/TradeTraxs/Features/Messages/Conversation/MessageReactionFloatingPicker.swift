import SwiftUI

/// Compact floating emoji bar for press-and-hold message reactions.
struct MessageReactionFloatingPicker: View {
    let supportedEmojis: [String]
    let onSelect: (String) -> Void
    let onDismiss: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: ExperienceSpacing.xs) {
            ForEach(supportedEmojis, id: \.self) { emoji in
                Button {
                    ExperienceHaptics.play(.selection)
                    onSelect(emoji)
                } label: {
                    Text(emoji)
                        .font(.title2)
                        .frame(width: 40, height: 40)
                        .background(colors.fillSecondary.opacity(0.95), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("message.reaction.picker.\(emoji)")
            }
        }
        .padding(.horizontal, ExperienceSpacing.sm)
        .padding(.vertical, ExperienceSpacing.xs)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("message.reaction.picker")
    }
}

/// Full-screen tap-catcher that dismisses the floating picker without blocking scroll.
struct MessageReactionPickerDismissOverlay: View {
    let onDismiss: () -> Void

    var body: some View {
        Color.black.opacity(0.001)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: onDismiss)
            .accessibilityHidden(true)
    }
}
