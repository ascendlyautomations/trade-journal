import Foundation

#if DEBUG
enum RoomTimelineTrace {
    static func log(stage: String, messages: [Message], extra: String = "") {
        let ids = messages.map(\.id.rawValue).joined(separator: ",")
        var line = "[RoomTimelineTrace] stage=\(stage) count=\(messages.count) ids=[\(ids)]"
        if !extra.isEmpty {
            line += " \(extra)"
        }
        print(line)
    }

    static func logHydration(stage: String, timelineCount: Int, tradeReferenceCount: Int, extra: String = "") {
        var line =
            "[RoomTimelineTrace] stage=\(stage) timelineCount=\(timelineCount) tradeReferenceCount=\(tradeReferenceCount)"
        if !extra.isEmpty {
            line += " \(extra)"
        }
        print(line)
    }
}
#endif
