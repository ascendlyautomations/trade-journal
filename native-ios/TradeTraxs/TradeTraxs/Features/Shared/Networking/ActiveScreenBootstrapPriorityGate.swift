import Foundation

/// When true, matching screen bootstrap RPCs use visible network scheduling (not background).
nonisolated enum ActiveScreenBootstrapPriorityGate {
    case messages
    case tradeRooms
    case feed

    private static let lock = NSLock()
    nonisolated(unsafe) private static var active: Set<String> = []

    func setScreenActive(_ active: Bool) {
        Self.lock.lock()
        if active {
            Self.active.insert(rawValue)
        } else {
            Self.active.remove(rawValue)
        }
        Self.lock.unlock()
    }

    var prefersVisibleBootstrap: Bool {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return Self.active.contains(rawValue)
    }

    private var rawValue: String {
        switch self {
        case .messages: return "messages"
        case .tradeRooms: return "tradeRooms"
        case .feed: return "feed"
        }
    }

    static func prefersVisibleBootstrap(rpcName: String) -> Bool {
        switch rpcName {
        case BackendV2Versioning.RPCName.messaging.rawValue:
            return ActiveScreenBootstrapPriorityGate.messages.prefersVisibleBootstrap
        case BackendV2Versioning.RPCName.tradeRoomsHomeBootstrap.rawValue:
            return ActiveScreenBootstrapPriorityGate.tradeRooms.prefersVisibleBootstrap
        case BackendV2Versioning.RPCName.feed.rawValue:
            return ActiveScreenBootstrapPriorityGate.feed.prefersVisibleBootstrap
        default:
            return false
        }
    }
}
