import Foundation
import Observation

/// Web `sessionStorage.pendingRoomShareDraft` — staged when Share Room chooses Create Feed Post.
@Observable
@MainActor
final class PendingRoomShareStore {
    static let shared = PendingRoomShareStore()

    private(set) var pending: RoomShareAttachment?

    private init() {}

    func stage(_ share: RoomShareAttachment) {
        pending = share
    }

    func consume() -> RoomShareAttachment? {
        defer { pending = nil }
        return pending
    }

    func clear() {
        pending = nil
    }
}
