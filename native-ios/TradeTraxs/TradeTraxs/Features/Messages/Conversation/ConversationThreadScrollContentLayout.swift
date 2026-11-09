import SwiftUI

/// Visible height of the message `ScrollView` — drives bottom-alignment for short threads.
private struct ConversationThreadScrollViewportHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// Pins thread content to the bottom when it is shorter than the scroll viewport (1–2 messages).
    func conversationThreadBottomAlignedContent(viewportHeight: CGFloat) -> some View {
        frame(
            maxWidth: .infinity,
            minHeight: max(viewportHeight, 1),
            alignment: .bottom
        )
    }

    /// Reads the scroll container height (composer + chrome already excluded by the parent layout).
    func conversationThreadScrollViewportReader(_ viewportHeight: Binding<CGFloat>) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ConversationThreadScrollViewportHeightKey.self,
                    value: geometry.size.height
                )
            }
        }
        .onPreferenceChange(ConversationThreadScrollViewportHeightKey.self) { height in
            guard height > 0, abs(viewportHeight.wrappedValue - height) > 0.5 else { return }
            viewportHeight.wrappedValue = height
        }
    }
}
