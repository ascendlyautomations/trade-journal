import SwiftUI

private struct MessageBubbleActionMenuAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [String: Anchor<CGRect>],
        nextValue: () -> [String: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func messageBubbleActionMenuAnchor(messageID: MessageID, isActive: Bool) -> some View {
        background {
            if isActive {
                Color.clear
                    .anchorPreference(key: MessageBubbleActionMenuAnchorKey.self, value: .bounds) { anchor in
                        [messageID.rawValue: anchor]
                    }
            }
        }
    }

    func messageBubbleActionMenuOverlay<Menu: View>(
        activeMessageID: Binding<MessageID?>,
        menuSize: @escaping (MessageID) -> CGSize,
        @ViewBuilder menu: @escaping (MessageID) -> Menu
    ) -> some View {
        overlayPreferenceValue(MessageBubbleActionMenuAnchorKey.self) { anchors in
            if let messageID = activeMessageID.wrappedValue {
                GeometryReader { geometry in
                    let anchorFrame = anchors[messageID.rawValue].map { geometry[$0] }
                    let size = menuSize(messageID)
                    ZStack {
                        Color.black.opacity(0.001)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                activeMessageID.wrappedValue = nil
                            }
                            .accessibilityHidden(true)

                        menu(messageID)
                            .fixedSize()
                            .position(
                                MessageBubbleActionMenuLayout.position(
                                    in: geometry.size,
                                    anchorFrame: anchorFrame,
                                    menuSize: size
                                )
                            )
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .animation(
            ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: false),
            value: activeMessageID.wrappedValue
        )
    }
}

private enum MessageBubbleActionMenuLayout {
    private static let verticalGap: CGFloat = 4
    private static let edgeMargin: CGFloat = 10

    static func position(
        in containerSize: CGSize,
        anchorFrame: CGRect?,
        menuSize: CGSize
    ) -> CGPoint {
        let halfW = menuSize.width / 2
        let halfH = menuSize.height / 2

        guard let anchorFrame else {
            return CGPoint(x: containerSize.width / 2, y: containerSize.height * 0.4)
        }

        var centerX = anchorFrame.midX
        centerX = min(
            max(centerX, edgeMargin + halfW),
            containerSize.width - edgeMargin - halfW
        )

        let belowY = anchorFrame.maxY + verticalGap + halfH
        let aboveY = anchorFrame.minY - verticalGap - halfH
        let fitsBelow = belowY + halfH <= containerSize.height - edgeMargin
        let centerY = fitsBelow ? belowY : max(edgeMargin + halfH, aboveY)

        return CGPoint(x: centerX, y: centerY)
    }
}
