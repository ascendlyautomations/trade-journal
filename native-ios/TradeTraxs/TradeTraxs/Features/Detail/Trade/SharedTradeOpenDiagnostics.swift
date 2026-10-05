import Foundation
import OSLog

#if DEBUG
/// Temporary tap → detail timing for shared/social trade opens (remove after hang is verified fixed).
enum SharedTradeOpenDiagnostics {
    private static var tapStartedAt: [String: CFAbsoluteTime] = [:]
    private static let lock = NSLock()

    static func tapped(tradeID: TradeID) {
        lock.lock()
        tapStartedAt[tradeID.rawValue] = CFAbsoluteTimeGetCurrent()
        lock.unlock()
        log(tradeID, event: "tapped")
    }

    static func destinationCreated(
        tradeID: TradeID,
        seedAvailable: Bool,
        handoffStaged: Bool = false,
        cacheInstance: ObjectIdentifier? = nil
    ) {
        var parts = ["destinationCreated", "seedAvailable=\(seedAvailable)", "handoffStaged=\(handoffStaged)"]
        if let cacheInstance {
            parts.append("cacheInstance=\(String(describing: cacheInstance))")
        }
        log(tradeID, event: parts.joined(separator: " "))
    }

    static func initialRender(
        tradeID: TradeID,
        state: String,
        cacheInstance: ObjectIdentifier? = nil,
        tradeNonNil: Bool? = nil
    ) {
        var parts = ["initialRender", "state=\(state)"]
        if let cacheInstance {
            parts.append("cacheInstance=\(String(describing: cacheInstance))")
        }
        if let tradeNonNil {
            parts.append("tradeNonNil=\(tradeNonNil)")
        }
        log(tradeID, event: parts.joined(separator: " "))
    }

    static func repositoryFetchStarted(tradeID: TradeID, step: String) {
        log(tradeID, event: "repositoryFetchStarted step=\(step)")
    }

    static func repositoryFetchFinished(tradeID: TradeID, step: String, outcome: String, elapsedMs: Int) {
        log(tradeID, event: "repositoryFetchFinished step=\(step) outcome=\(outcome) elapsedMs=\(elapsedMs)")
    }

    static func hydrationStarted(tradeID: TradeID, source: String) {
        log(tradeID, event: "hydrationStarted source=\(source)")
    }

    static func hydrationResponse(tradeID: TradeID, status: String, elapsedMs: Int) {
        log(tradeID, event: "hydrationResponse status=\(status) elapsedMs=\(elapsedMs)")
    }

    static func hydrationDecoded(tradeID: TradeID) {
        log(tradeID, event: "hydrationDecoded")
    }

    static func statePublished(tradeID: TradeID) {
        log(tradeID, event: "statePublished")
    }

    static func contentRendered(tradeID: TradeID) {
        log(tradeID, event: "contentRendered totalMs=\(elapsedSinceTap(tradeID))")
        clearTap(tradeID)
    }

    static func hydrationFailed(tradeID: TradeID, error: String) {
        log(tradeID, event: "hydrationFailed error=\(error)")
    }

    static func hydrationCancelled(tradeID: TradeID, reason: String) {
        log(tradeID, event: "hydrationCancelled reason=\(reason)")
    }

    private static func log(_ tradeID: TradeID, event: String) {
        let line = "[SharedTradeOpen] tradeID=\(tradeID.rawValue) event=\(event)"
        print(line)
        AppLog.navigation.info("\(line, privacy: .public)")
    }

    private static func elapsedSinceTap(_ tradeID: TradeID) -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard let start = tapStartedAt[tradeID.rawValue] else { return 0 }
        return Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }

    private static func clearTap(_ tradeID: TradeID) {
        lock.lock()
        tapStartedAt.removeValue(forKey: tradeID.rawValue)
        lock.unlock()
    }
}
#endif
