import Foundation
import os

/// Non-sensitive rejoin diagnostics — room id hashes, row counts, active flag only.
enum TradeRoomMembershipRejoinTrace {
    private nonisolated static let log = Logger(subsystem: "com.tradetraxs.trade-rooms", category: "membership-rejoin")

    struct ReactivateOutcome: Sendable {
        var roomID: String
        var returnedRowCount: Int
        var leftAtClearedInResponse: Bool?
        var activeMembershipConfirmed: Bool
    }

    nonisolated static func logReactivate(_ outcome: ReactivateOutcome) {
        let cleared = outcome.leftAtClearedInResponse.map { $0 ? "yes" : "no" } ?? "unknown"
        log.info(
            "reactivate room=\(outcome.roomID, privacy: .public) rows=\(outcome.returnedRowCount, privacy: .public) left_at_cleared=\(cleared, privacy: .public) active_confirmed=\(outcome.activeMembershipConfirmed, privacy: .public)"
        )
    }

    nonisolated static func logJoinConfirmFailed(roomID: String) {
        log.warning("join_confirm_failed room=\(roomID, privacy: .public) active_row_missing_after_patch")
    }

    nonisolated static func logJoinRequestProbe(roomID: String, status: String?) {
        log.info(
            "join_request_probe room=\(roomID, privacy: .public) status=\(status ?? "nil", privacy: .public)"
        )
    }
}

#if DEBUG
extension TradeRoomMembershipRejoinTrace {
    nonisolated static func debugPrint(_ message: String) {
        print("[TradeRoomMembershipRejoin] \(message)")
    }
}
#endif