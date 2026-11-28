import Foundation

/// Batched creator share events (`rpc_v1_creator_record_shares`).
@MainActor
enum CreatorShareTracking {
    private static var rpc: (any RPCClient)?

    static func configure(rpc: (any RPCClient)?) {
        self.rpc = rpc
    }

    static func recordInitiated(for target: SharedContentShareTarget) {
        enqueue(target: target, phase: "initiated")
    }

    static func recordCompleted(for target: SharedContentShareTarget) {
        enqueue(target: target, phase: "completed")
    }

    private static func enqueue(target: SharedContentShareTarget, phase: String) {
        guard BackendV2FeatureFlags.isEnabled(.profileInsights)
            || BackendV2FeatureFlags.isEnabled(.feedRotatingRank)
        else { return }
        guard let rpc, let item = rpcItem(for: target.reference) else { return }

        struct Payload: Encodable {
            var content_kind: String
            var content_id: String
            var share_phase: String
            var platform: String = "ios"
        }

        struct Args: Encodable { var p_items: [Payload] }

        let body: Data
        do {
            body = try JSONEncoder().encode(
                Args(p_items: [Payload(content_kind: item.kind, content_id: item.id, share_phase: phase)])
            )
        } catch {
            return
        }

        Task {
            _ = try? await rpc.call(
                functionName: BackendV2Versioning.RPCName.creatorRecordShares.rawValue,
                jsonBody: body
            )
        }
    }

    private static func rpcItem(for reference: SharedContentReference) -> (kind: String, id: String)? {
        switch reference {
        case .feedPost(let id):
            return ("post", id.rawValue)
        case .profilePost(let id):
            return ("profile_post", id.rawValue)
        case .achievementPost(let id):
            return ("achievement_post", id.rawValue)
        case .reel(let id):
            return ("reel", id.rawValue)
        case .traderProfile(let id):
            return ("trader_profile", id.rawValue)
        case .trade:
            return nil
        }
    }
}