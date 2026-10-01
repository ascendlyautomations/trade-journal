import XCTest
@testable import TradeTraxs

final class OwnedMediaStorageCleanupTests: XCTestCase {
    func testParsesPublicObjectURL() {
        let location = OwnedMediaStorageCleanup.location(
            fromPublicURL: "https://proj.supabase.co/storage/v1/object/public/reels/user-1/videos/clip.mp4"
        )
        XCTAssertEqual(location?.bucket, "reels")
        XCTAssertEqual(location?.path, "user-1/videos/clip.mp4")
    }

    func testIgnoresNonStorageURLsAndTraversal() {
        XCTAssertNil(OwnedMediaStorageCleanup.location(fromPublicURL: "https://example.com/clip.mp4"))
        XCTAssertNil(
            OwnedMediaStorageCleanup.location(
                fromPublicURL: "https://proj.supabase.co/storage/v1/object/public/reels/../secrets"
            )
        )
        XCTAssertNil(OwnedMediaStorageCleanup.location(fromPublicURL: nil))
    }
}
