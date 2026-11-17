import Foundation

enum TradeRoomBroadcastStreamTitle {
    static let maxLength = 100

    static func normalize(_ raw: String) -> String? {
        let collapsed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard !collapsed.isEmpty else { return nil }
        if collapsed.count > maxLength {
            return String(collapsed.prefix(maxLength))
        }
        return collapsed
    }

    /// Viewer sheet — stream title first, then trade room name, single-line with truncation.
    static func viewerPopupHeadline(streamTitle: String?, roomName: String) -> String {
        let room = roomName.trimmingCharacters(in: .whitespacesAndNewlines)
        let roomDisplay = room.isEmpty ? "Trade Room" : room
        if let title = normalize(streamTitle ?? "") {
            return "\(title) | \(roomDisplay)"
        }
        return roomDisplay
    }

    static func headline(
        broadcasterName: String?,
        streamTitle: String?,
        roomFallback: String?
    ) -> String {
        let name = broadcasterName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Trader"
        let title =
            normalize(streamTitle ?? "")
            ?? roomFallback?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? "Live stream"
        return "\(name) · \(title)"
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
