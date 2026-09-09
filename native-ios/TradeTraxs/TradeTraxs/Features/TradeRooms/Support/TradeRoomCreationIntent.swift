import Foundation
import Observation

/// Explicit presentation intent for opening Create Trade Room from Profile.
@Observable
@MainActor
final class TradeRoomCreationIntent {
    static let shared = TradeRoomCreationIntent()

    private(set) var pendingPresentCreate = false
    private(set) var createdRoomForProfile: TradeRoom?

    private init() {}

    func requestCreateFromProfile() {
        pendingPresentCreate = true
    }

    /// Returns true once when create should auto-present on Trade Rooms home.
    func consumePresentCreate() -> Bool {
        guard pendingPresentCreate else { return false }
        pendingPresentCreate = false
        return true
    }

    func noteCreatedRoom(_ room: TradeRoom) {
        createdRoomForProfile = room
    }

    func consumeCreatedRoomForProfile() -> TradeRoom? {
        defer { createdRoomForProfile = nil }
        return createdRoomForProfile
    }
}
