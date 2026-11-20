import SwiftUI
import XCTest
@testable import TradeTraxs

final class BroadcastMiniPlayerLayoutTests: XCTestCase {
    func testTopCornerAnchorRespectsSafeAreaPlusExtraPadding() {
        let safeArea = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
        let layout = BroadcastMiniPlayerLayout.makeLayout(
            containerSize: CGSize(width: 390, height: 844),
            safeArea: safeArea,
            tabBarTopInsetFromBottom: 83,
            horizontalMargin: 12,
            verticalMargin: 10,
            maxPlayerWidth: 200,
            widthToScreenRatio: 0.44
        )
        let topY = layout.draggableBounds.minY
        let topSafe = BroadcastMiniPlayerLayout.resolvedTopSafeArea(safeArea)
        let expectedTop = topSafe + BroadcastMiniPlayerLayout.topCornerExtraPadding + layout.playerSize.height / 2
        XCTAssertEqual(topY, expectedTop, accuracy: 0.01)
        XCTAssertEqual(
            BroadcastMiniPlayerLayout.center(for: .topLeading, playerSize: layout.playerSize, in: layout.draggableBounds).y,
            topY
        )
    }

    func testTopCornerUsesKeyWindowWhenSwiftUISafeAreaTopIsZero() {
        let layout = BroadcastMiniPlayerLayout.makeLayout(
            containerSize: CGSize(width: 390, height: 844),
            safeArea: EdgeInsets(),
            tabBarTopInsetFromBottom: 83,
            horizontalMargin: 12,
            verticalMargin: 10,
            maxPlayerWidth: 200,
            widthToScreenRatio: 0.44
        )
        let windowTop = BroadcastMiniPlayerLayout.resolvedTopSafeArea(EdgeInsets())
        let expectedTop = windowTop + BroadcastMiniPlayerLayout.topCornerExtraPadding + layout.playerSize.height / 2
        XCTAssertEqual(layout.draggableBounds.minY, expectedTop, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(BroadcastMiniPlayerLayout.topCornerExtraPadding, 12)
        XCTAssertLessThanOrEqual(BroadcastMiniPlayerLayout.topCornerExtraPadding, 16)
    }

    func testNearestCornerSnapsToQuadrant() {
        let size = CGSize(width: 180, height: 180 * 9 / 16)
        let bounds = CGRect(x: 100, y: 120, width: 200, height: 400)

        XCTAssertEqual(
            BroadcastMiniPlayerLayout.nearestCorner(to: CGPoint(x: 110, y: 130), playerSize: size, in: bounds),
            .topLeading
        )
        XCTAssertEqual(
            BroadcastMiniPlayerLayout.nearestCorner(to: CGPoint(x: 290, y: 130), playerSize: size, in: bounds),
            .topTrailing
        )
        XCTAssertEqual(
            BroadcastMiniPlayerLayout.nearestCorner(to: CGPoint(x: 110, y: 500), playerSize: size, in: bounds),
            .bottomLeading
        )
        XCTAssertEqual(
            BroadcastMiniPlayerLayout.nearestCorner(to: CGPoint(x: 290, y: 500), playerSize: size, in: bounds),
            .bottomTrailing
        )
    }
}