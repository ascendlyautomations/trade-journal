import Foundation

/// PostgREST PATCH body for self-rejoin, must emit explicit JSON `null` for `left_at`
/// (Swift's default `Encodable` omits `nil` optionals and would not clear soft leave).
struct TradeRoomMembershipRejoinPatchBody: Encodable, Sendable {
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNil(forKey: .left_at)
        try container.encode(true, forKey: .notification_enabled)
    }

    private enum CodingKeys: String, CodingKey {
        case left_at
        case notification_enabled
    }
}