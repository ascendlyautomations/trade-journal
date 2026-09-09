import Foundation
import OSLog

#if DEBUG
enum PayoutBatchDiagnostics {
    static func logEntries(accounts: Int, requests: Int, entries: Int, dtMs: Int) {
        AppLog.general.debug(
            "[PayoutBatch] accounts=\(accounts, privacy: .public) requests=\(requests, privacy: .public) entries=\(entries, privacy: .public) dtMs=\(dtMs, privacy: .public)"
        )
    }

    static func logCycles(accounts: Int, requests: Int, cycles: Int, dtMs: Int) {
        AppLog.general.debug(
            "[PayoutBatch] accounts=\(accounts, privacy: .public) requests=\(requests, privacy: .public) cycles=\(cycles, privacy: .public) dtMs=\(dtMs, privacy: .public)"
        )
    }
}
#else
enum PayoutBatchDiagnostics {
    static func logEntries(accounts: Int, requests: Int, entries: Int, dtMs: Int) {}
    static func logCycles(accounts: Int, requests: Int, cycles: Int, dtMs: Int) {}
}
#endif
