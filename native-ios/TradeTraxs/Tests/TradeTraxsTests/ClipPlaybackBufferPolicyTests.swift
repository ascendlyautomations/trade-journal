import XCTest
@testable import TradeTraxs

final class ClipPlaybackBufferPolicyTests: XCTestCase {
    func testWiFiKeepsNeighborPrefetchAndShortBufferWithoutStallMinimization() {
        let configuration = ClipPlaybackBufferConfiguration.make(for: .wifi)
        XCTAssertEqual(configuration.networkClass, "wifi")
        XCTAssertTrue(configuration.allowsNeighborPrefetch)
        XCTAssertEqual(configuration.activeForwardBufferSeconds, 2)
        XCTAssertEqual(configuration.prefetchForwardBufferSeconds, 1)
        XCTAssertFalse(configuration.waitsToMinimizeStalling)
        XCTAssertTrue(ClipPlaybackBufferConfiguration.allowsPersistentFullFileFill(posture: .wifi))
    }

    func testCellularSkipsNeighborPrefetchAndFullFileFill() {
        let configuration = ClipPlaybackBufferConfiguration.make(for: .cellular)
        XCTAssertEqual(configuration.networkClass, "cellular")
        XCTAssertFalse(configuration.allowsNeighborPrefetch)
        XCTAssertEqual(configuration.activeForwardBufferSeconds, 1)
        XCTAssertFalse(configuration.waitsToMinimizeStalling)
        XCTAssertFalse(ClipPlaybackBufferConfiguration.allowsPersistentFullFileFill(posture: .cellular))
    }

    func testConstrainedAndExpensivePathsConserveBandwidth() {
        let constrained = ClipPlaybackNetworkPosture(
            isOnline: true,
            isExpensive: false,
            isConstrained: true,
            usesCellular: false
        )
        let expensive = ClipPlaybackNetworkPosture(
            isOnline: true,
            isExpensive: true,
            isConstrained: false,
            usesCellular: false
        )
        let offline = ClipPlaybackNetworkPosture(
            isOnline: false,
            isExpensive: false,
            isConstrained: false,
            usesCellular: false
        )

        XCTAssertEqual(ClipPlaybackBufferConfiguration.make(for: constrained).networkClass, "constrained")
        XCTAssertFalse(ClipPlaybackBufferConfiguration.make(for: constrained).allowsNeighborPrefetch)
        XCTAssertEqual(ClipPlaybackBufferConfiguration.make(for: expensive).networkClass, "expensive")
        XCTAssertFalse(ClipPlaybackBufferConfiguration.make(for: expensive).allowsNeighborPrefetch)
        XCTAssertEqual(ClipPlaybackBufferConfiguration.make(for: offline).networkClass, "offline")
        XCTAssertFalse(ClipPlaybackBufferConfiguration.allowsPersistentFullFileFill(posture: offline))
    }

    func testTransferRatioMatchesAggressiveProgressiveDownload() {
        let assetBytes: Int64 = 53_000_000
        let transferred: Int64 = 32_000_000
        let playbackSeconds = 1.3
        let perSecond = ClipPlaybackTransferMetrics.bytesPerPlaybackSecond(
            bytesTransferred: transferred,
            playbackSeconds: playbackSeconds
        )
        let fraction = ClipPlaybackTransferMetrics.assetFraction(
            bytesTransferred: transferred,
            assetBytes: assetBytes
        )
        XCTAssertEqual(perSecond ?? 0, Double(transferred) / playbackSeconds, accuracy: 1)
        XCTAssertEqual(fraction ?? 0, Double(transferred) / Double(assetBytes), accuracy: 0.001)
        XCTAssertGreaterThan(fraction ?? 0, 0.5)
    }
}
