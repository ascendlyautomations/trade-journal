import SwiftUI

private struct MessageReactionPickerAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [String: Anchor<CGRect>],
        nextValue: () -> [String: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    /// Registers a picker anchor for the active long-press target only (no per-row GeometryReader).
    func messageReactionPickerAnchor(messageID: MessageID, isActive: Bool) -> some View {
        background {
            if isActive {
                Color.clear
                    .anchorPreference(key: MessageReactionPickerAnchorKey.self, value: .bounds) { anchor in
                        [messageID.rawValue: anchor]
                    }
            }
        }
    }

    /// Floating emoji bar + dismiss tap-catcher for press-and-hold reactions.
    func messageReactionPickerOverlay(
        pickerMessageID: Binding<MessageID?>,
        onSelect: @escaping (MessageID, String) -> Void
    ) -> some View {
        overlayPreferenceValue(MessageReactionPickerAnchorKey.self) { anchors in
            if let messageID = pickerMessageID.wrappedValue {
                GeometryReader { geometry in
                    let frame = anchors[messageID.rawValue].map { geometry[$0] }
                    ZStack {
                        MessageReactionPickerDismissOverlay {
                            pickerMessageID.wrappedValue = nil
                        }
                        MessageReactionFloatingPicker(
                            supportedEmojis: MessageReactionSemantics.supportedEmojis,
                            onSelect: { emoji in
                                pickerMessageID.wrappedValue = nil
                                onSelect(messageID, emoji)
                            },
                            onDismiss: {
                                pickerMessageID.wrappedValue = nil
                            }
                        )
                        .position(
                            MessageReactionPickerLayout.position(
                                in: geometry.size,
                                anchorFrame: frame
                            )
                        )
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .animation(
            ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: false),
            value: pickerMessageID.wrappedValue
        )
    }
}

private enum MessageReactionPickerLayout {
    static func position(in containerSize: CGSize, anchorFrame: CGRect?) -> CGPoint {
        let pickerHeight: CGFloat = 52
        let margin: CGFloat = 12
        let x = min(
            max(anchorFrame?.midX ?? containerSize.width / 2, margin + 120),
            containerSize.width - margin - 120
        )
        if let anchorFrame {
            let above = anchorFrame.minY - pickerHeight - margin
            if above > margin + 44 {
                return CGPoint(x: x, y: above + pickerHeight / 2)
            }
            let below = anchorFrame.maxY + pickerHeight / 2 + margin
            return CGPoint(x: x, y: min(below, containerSize.height - margin - pickerHeight / 2))
        }
        return CGPoint(x: containerSize.width / 2, y: containerSize.height * 0.35)
    }
}
