import Foundation

/// Waits for an async operation without propagating structured-task cancellation to the caller.
nonisolated enum UncancelledWait {
    static func run<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            Task.detached {
                do {
                    let value = try await operation()
                    continuation.resume(returning: value)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

/// Process-wide Backend V2 RPC single-flight — one underlying Task per canonical key.
///
/// Equivalent callers share one detached fetch. One waiter cancelling does **not**
/// cancel the shared transport for other active waiters.
actor BackendV2SingleFlight {
    static let shared = BackendV2SingleFlight()

    private struct Slot {
        let id: UUID
        let task: Task<Data, Error>
        var waiterCount: Int
    }

    private var inFlight: [String: Slot] = [:]

    /// Runs `fetch` once per key; concurrent callers await the same detached task.
    func coalesce(key: String, fetch: @escaping @Sendable () async throws -> Data) async throws -> Data {
        let slotID: UUID
        let task: Task<Data, Error>

        if var existing = inFlight[key] {
            existing.waiterCount += 1
            inFlight[key] = existing
            slotID = existing.id
            task = existing.task
        } else {
            slotID = UUID()
            let capturedID = slotID
            let detached = Task.detached(priority: .userInitiated) {
                try await fetch()
            }
            task = detached
            inFlight[key] = Slot(id: capturedID, task: detached, waiterCount: 1)

            Task { [self] in
                _ = await detached.result
                finishSlot(key: key, slotID: capturedID)
            }
        }

        defer {
            leaveWaiter(key: key, slotID: slotID)
        }

        return try await UncancelledWait.run {
            try await task.value
        }
    }

    func clear(viewerID: String? = nil) {
        if let viewerID {
            let prefix = "\(viewerID)|"
            for (key, slot) in inFlight where key.hasPrefix(prefix) {
                slot.task.cancel()
                inFlight[key] = nil
            }
        } else {
            for slot in inFlight.values {
                slot.task.cancel()
            }
            inFlight.removeAll()
        }
    }

    /// Test seam — whether a key currently has an in-flight shared task.
    func hasInFlight(key: String) -> Bool {
        inFlight[key] != nil
    }

    func inFlightWaiterCount(key: String) -> Int {
        inFlight[key]?.waiterCount ?? 0
    }

    private func leaveWaiter(key: String, slotID: UUID) {
        guard var slot = inFlight[key], slot.id == slotID else { return }
        slot.waiterCount = max(0, slot.waiterCount - 1)
        inFlight[key] = slot
    }

    /// Removes the keyed slot once the underlying detached task has finished.
    /// Waiters retain their local `Task` reference and still receive the result.
    private func finishSlot(key: String, slotID: UUID) {
        guard let slot = inFlight[key], slot.id == slotID else { return }
        inFlight[key] = nil
    }
}

nonisolated enum BackendV2FlightKeys {
    static func session(viewerID: String) -> String {
        "\(viewerID)|\(BackendV2Versioning.RPCName.session.rawValue)"
    }

    static func dashboard(viewerID: String, accountID: String?) -> String {
        let account = accountID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? accountID!
            : "all"
        return "\(viewerID)|\(BackendV2Versioning.RPCName.dashboard.rawValue)|\(account)"
    }

    static func feed(
        viewerID: String,
        scope: String,
        contentFilter: String,
        cursor: String?
    ) -> String {
        let c = cursor ?? "-"
        return "\(viewerID)|\(BackendV2Versioning.RPCName.feed.rawValue)|\(scope)|\(contentFilter)|\(c)"
    }

    static func messaging(viewerID: String, cursor: String?) -> String {
        let c = cursor ?? "-"
        return "\(viewerID)|\(BackendV2Versioning.RPCName.messaging.rawValue)|\(c)"
    }

    static func conversationThread(
        viewerID: String,
        conversationID: String,
        cursor: String?,
        markRead: Bool
    ) -> String {
        let c = cursor ?? "-"
        return "\(viewerID)|\(BackendV2Versioning.RPCName.conversationThread.rawValue)|\(conversationID)|\(c)|read=\(markRead)"
    }

    static func profile(profileID: String) -> String {
        "\(profileID)|\(BackendV2Versioning.RPCName.profile.rawValue)"
    }

    static func room(viewerID: String, roomID: String, sectionID: String?) -> String {
        let section = sectionID ?? "-"
        return "\(viewerID)|\(BackendV2Versioning.RPCName.room.rawValue)|\(roomID)|\(section)"
    }

    static func propFirm(viewerID: String) -> String {
        "\(viewerID)|\(BackendV2Versioning.RPCName.propFirm.rawValue)"
    }

    static func activity(viewerID: String, cursor: String?) -> String {
        let c = cursor ?? "-"
        return "\(viewerID)|\(BackendV2Versioning.RPCName.activity.rawValue)|\(c)"
    }

    static func explore(viewerID: String, traderOffset: Int) -> String {
        "\(viewerID)|\(BackendV2Versioning.RPCName.explore.rawValue)|\(traderOffset)"
    }

    static func calendar(viewerID: String, year: Int, month: Int, accountID: String?) -> String {
        let account = accountID ?? "all"
        return "\(viewerID)|\(BackendV2Versioning.RPCName.calendar.rawValue)|\(year)-\(month)|\(account)"
    }

    static func tradesList(viewerID: String, queryKey: String, cursor: String?) -> String {
        let c = cursor ?? "-"
        return "\(viewerID)|\(BackendV2Versioning.RPCName.tradesList.rawValue)|\(queryKey)|\(c)"
    }
}
