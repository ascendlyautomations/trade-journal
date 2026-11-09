import Foundation
import OSLog

/// Runtime breadcrumbs for Trade Room push → sub-room selection.
///
/// Filter Console with subsystem `com.tradetraxs.app` and category `roomNotificationNav`.
enum RoomNotificationNavigationTrace {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.tradetraxs.app",
        category: "roomNotificationNav"
    )

    struct Payload: Sendable {
        var stage: String
        var roomID: String?
        var sectionID: String?
        var sectionName: String?
        var messageID: String?
        var destination: String?
        var presentationID: String?
        var epoch: Int?
        var focusToken: String?
        var selectedChannelID: String?
        var vmIdentity: ObjectIdentifier?
        var channelIDs: [String]?
        var detail: String?
    }

    @MainActor
    static func event(_ payload: Payload) {
        var parts: [String] = ["stage=\(payload.stage)"]
        if let roomID = payload.roomID { parts.append("room=\(roomID)") }
        if let sectionID = payload.sectionID { parts.append("section=\(sectionID)") }
        if let sectionName = payload.sectionName { parts.append("sectionName=\(sectionName)") }
        if let messageID = payload.messageID { parts.append("message=\(messageID)") }
        if let destination = payload.destination { parts.append("dest=\(destination)") }
        if let presentationID = payload.presentationID { parts.append("presentation=\(presentationID)") }
        if let epoch = payload.epoch { parts.append("epoch=\(epoch)") }
        if let focusToken = payload.focusToken { parts.append("focusToken=\(focusToken)") }
        if let selectedChannelID = payload.selectedChannelID { parts.append("selected=\(selectedChannelID)") }
        if let vmIdentity = payload.vmIdentity { parts.append("vm=\(String(describing: vmIdentity))") }
        if let channelIDs = payload.channelIDs, !channelIDs.isEmpty {
            parts.append("channels=[\(channelIDs.joined(separator: ","))]")
        }
        if let detail = payload.detail { parts.append(detail) }
        let line = parts.joined(separator: " ")
        logger.info("\(line, privacy: .public)")
        #if DEBUG
        print("[RoomNotificationNav] \(line)")
        #endif
    }
}
