import AVFoundation
import Foundation

#if DEBUG
/// DEBUG-only Clips player identity — correlates with ``VideoTransferAudit`` instance IDs.
enum ClipPlayerLifecycle {
    static func log(
        clipID: String,
        player: AVPlayer?,
        item: AVPlayerItem?,
        event: String,
        reason: String
    ) {
        let playerID = player.map { String(describing: ObjectIdentifier($0)) } ?? "nil"
        let itemID = item.map { String(describing: ObjectIdentifier($0)) } ?? "nil"
        print(
            """
            [ClipPlayerLifecycle] \
            clipID=\(clipID) \
            playerInstanceID=\(playerID) \
            itemInstanceID=\(itemID) \
            event=\(event) \
            reason=\(reason)
            """
        )
    }
}
#else
enum ClipPlayerLifecycle {
    static func log(
        clipID: String,
        player: AVPlayer?,
        item: AVPlayerItem?,
        event: String,
        reason: String
    ) {}
}
#endif
