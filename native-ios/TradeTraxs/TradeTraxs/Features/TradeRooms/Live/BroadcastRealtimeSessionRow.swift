import Foundation

enum BroadcastRealtimeSessionRow {
    nonisolated static func endedAt(from payload: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            return nil
        }
        return object["ended_at"] as? String
    }
}