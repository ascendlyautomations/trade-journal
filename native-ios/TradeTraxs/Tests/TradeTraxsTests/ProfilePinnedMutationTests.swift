import XCTest
@testable import TradeTraxs

final class ProfilePinnedMutationTests: XCTestCase {
    private func item(
        type: ProfilePinnedContentType,
        id: String,
        position: Int
    ) -> ProfilePinnedItem {
        ProfilePinnedItem(
            contentType: type,
            contentID: id,
            position: position,
            preview: ProfilePinnedPreview(
                kindLabel: type.displayLabel,
                title: id,
                subtitle: nil,
                imageURL: nil,
                body: nil,
                valueText: nil
            )
        )
    }

    func testInsertUsesNextAvailablePosition() {
        let current = [
            item(type: .trade, id: "t1", position: 1),
            item(type: .profilePost, id: "p1", position: 2),
        ]
        let request = ProfilePinRequest(
            contentType: .achievement,
            contentID: "a1",
            replacePosition: nil
        )
        let preview = ProfilePinnedPreview(
            kindLabel: "Achievement",
            title: "Payout",
            subtitle: nil,
            imageURL: nil,
            body: nil,
            valueText: "$2,500"
        )
        let result = ProfilePinnedMutation.insert(
            request: request,
            preview: preview,
            into: current
        )
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.map(\.position).sorted(), [1, 2, 3])
        XCTAssertTrue(result.contains { $0.contentID == "a1" && $0.position == 3 })
    }

    func testReplaceSwapsSelectedSlot() {
        let current = [
            item(type: .trade, id: "t1", position: 1),
            item(type: .profilePost, id: "p1", position: 2),
            item(type: .achievement, id: "a1", position: 3),
        ]
        let request = ProfilePinRequest(
            contentType: .profilePost,
            contentID: "p2",
            replacePosition: 2
        )
        let preview = ProfilePinnedPreview(
            kindLabel: "Post",
            title: "New post",
            subtitle: nil,
            imageURL: nil,
            body: "caption",
            valueText: nil
        )
        let result = ProfilePinnedMutation.insert(
            request: request,
            preview: preview,
            into: current
        )
        XCTAssertEqual(result.map(\.contentID).sorted(), ["a1", "p2", "t1"])
        XCTAssertFalse(result.contains { $0.contentID == "p1" })
        XCTAssertEqual(result.first(where: { $0.contentID == "p2" })?.position, 2)
    }

    func testRemoveShiftsPositionsDown() {
        let current = [
            item(type: .trade, id: "t1", position: 1),
            item(type: .profilePost, id: "p1", position: 2),
            item(type: .achievement, id: "a1", position: 3),
        ]
        let result = ProfilePinnedMutation.remove(
            contentType: .profilePost,
            contentID: "p1",
            from: current
        )
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first(where: { $0.contentID == "a1" })?.position, 2)
        XCTAssertEqual(result.first(where: { $0.contentID == "t1" })?.position, 1)
    }

    func testSwapPositions() {
        let current = [
            item(type: .trade, id: "t1", position: 1),
            item(type: .profilePost, id: "p1", position: 2),
            item(type: .achievement, id: "a1", position: 3),
        ]
        let result = ProfilePinnedMutation.swapPositions(from: 1, to: 3, in: current)
        XCTAssertEqual(result.first(where: { $0.contentID == "t1" })?.position, 3)
        XCTAssertEqual(result.first(where: { $0.contentID == "a1" })?.position, 1)
    }
}
