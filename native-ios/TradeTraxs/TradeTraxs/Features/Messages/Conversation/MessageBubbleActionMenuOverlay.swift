import SwiftUI

private struct MessageBubbleActionMenuAnchorValue {
    var anchor: Anchor<CGRect>
    var isOutgoing: Bool
}

private struct MessageBubbleActionMenuAnchorKey: PreferenceKey {
    static var defaultValue: [String: MessageBubbleActionMenuAnchorValue] = [:]

    static func reduce(
        value: inout [String: MessageBubbleActionMenuAnchorValue],
        nextValue: () -> [String: MessageBubbleActionMenuAnchorValue]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func messageBubbleActionMenuAnchor(
        messageID: MessageID,
        isOutgoing: Bool,
        isActive: Bool
    ) -> some View {
        background {
            if isActive {
                Color.clear
                    .anchorPreference(key: MessageBubbleActionMenuAnchorKey.self, value: .bounds) { anchor in
                        [
                            messageID.rawValue: MessageBubbleActionMenuAnchorValue(
                                anchor: anchor,
                                isOutgoing: isOutgoing
                            )
                        ]
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
            if let messageID = activeMessageID.wrappedValue,
               let anchor = anchors[messageID.rawValue] {
                GeometryReader { geometry in
                    let anchorFrame = geometry[anchor.anchor]
                    ZStack {
                        Color.black.opacity(0.001)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                activeMessageID.wrappedValue = nil
                            }
                            .accessibilityHidden(true)

                        MessageBubbleActionMenuHost(
                            anchorFrame: anchorFrame,
                            isOutgoing: anchor.isOutgoing,
                            containerSize: geometry.size,
                            safeInsets: geometry.safeAreaInsets,
                            fallbackSize: menuSize(messageID),
                            menu: menu(messageID)
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

private struct MessageBubbleActionMenuHost<Menu: View>: View {
    let anchorFrame: CGRect
    let isOutgoing: Bool
    let containerSize: CGSize
    let safeInsets: EdgeInsets
    let fallbackSize: CGSize
    let menu: Menu

    @State private var measuredSize: CGSize?

    var body: some View {
        menu
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { newSize in
                if measuredSize != newSize {
                    measuredSize = newSize
                }
            }
            .position(
                MessageBubbleActionMenuLayout.position(
                    in: containerSize,
                    safeInsets: safeInsets,
                    anchorFrame: anchorFrame,
                    isOutgoing: isOutgoing,
                    menuSize: measuredSize ?? fallbackSize
                )
            )
    }
}

enum MessageBubbleActionMenuLayout {
    static let verticalGap: CGFloat = 6
    static let minimumEdgeMargin: CGFloat = 12

    static func position(
        in containerSize: CGSize,
        safeInsets: EdgeInsets = EdgeInsets(),
        anchorFrame: CGRect,
        isOutgoing: Bool,
        menuSize: CGSize
    ) -> CGPoint {
        let halfW = menuSize.width / 2
        let halfH = menuSize.height / 2
        let leading = max(minimumEdgeMargin, safeInsets.leading)
        let trailing = max(minimumEdgeMargin, safeInsets.trailing)
        let top = max(minimumEdgeMargin, safeInsets.top)
        let bottom = max(minimumEdgeMargin, safeInsets.bottom)

        let minCenterX = leading + halfW
        let maxCenterX = containerSize.width - trailing - halfW
        // Outbound: menu's right edge meets the bubble's right edge and grows left.
        // Incoming: menu's left edge meets the bubble's left edge and grows right.
        let alignedCenterX = isOutgoing
            ? anchorFrame.maxX - halfW
            : anchorFrame.minX + halfW
        let centerX = min(max(alignedCenterX, minCenterX), max(minCenterX, maxCenterX))

        let minCenterY = top + halfH
        let maxCenterY = containerSize.height - bottom - halfH
        let belowY = anchorFrame.maxY + verticalGap + halfH
        let aboveY = anchorFrame.minY - verticalGap - halfH
        let fitsBelow = belowY <= maxCenterY
        let fitsAbove = aboveY >= minCenterY
        let preferredY: CGFloat
        if fitsBelow {
            preferredY = belowY
        } else if fitsAbove {
            preferredY = aboveY
        } else {
            let spaceBelow = containerSize.height - bottom - anchorFrame.maxY
            let spaceAbove = anchorFrame.minY - top
            preferredY = spaceBelow >= spaceAbove ? belowY : aboveY
        }
        let centerY = min(max(preferredY, minCenterY), max(minCenterY, maxCenterY))

        return CGPoint(x: centerX, y: centerY)
    }
}
