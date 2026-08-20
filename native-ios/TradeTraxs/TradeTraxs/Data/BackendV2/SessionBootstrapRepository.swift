import Foundation
import os

/// REST session bootstrap — mirrors web SessionRestBootstrapRepository (for dual-run).
/// Not used when backendV2.session is OFF.
nonisolated struct SessionRestBootstrapRepository: SessionBootstrapProviding {
    private let profiles: any ProfileRepository
    private let session: any SessionProviding
    private let trades: any TradeRepository
    private let notifications: any NotificationRepository
    private let messages: any MessageRepository
    private let notificationPreferences: any NotificationPreferencesRepository

    init(
        profiles: any ProfileRepository,
        session: any SessionProviding,
        trades: any TradeRepository,
        notifications: any NotificationRepository,
        messages: any MessageRepository,
        notificationPreferences: any NotificationPreferencesRepository
    ) {
        self.profiles = profiles
        self.session = session
        self.trades = trades
        self.notifications = notifications
        self.messages = messages
        self.notificationPreferences = notificationPreferences
    }

    func loadSessionBootstrap() async throws -> SessionBootstrapV1 {
        throw BackendV2RPCError.notImplemented(
            "SessionRestBootstrapRepository dual-run uses web REST composition; iOS dual-run compares RPC decode + following/badge seeds only"
        )
    }
}

/// RPC session bootstrap — calls `rpc_v1_session_bootstrap`.
nonisolated struct SessionRpcBootstrapRepository: SessionBootstrapProviding {
    private let client: BackendV2RPCClient

    init(rpc: any RPCClient) {
        self.client = BackendV2RPCClient(transport: rpc)
    }

    func loadSessionBootstrap() async throws -> SessionBootstrapV1 {
        let value = try await client.call(
            .session,
            as: SessionBootstrapV1.self,
            options: BackendV2RPCCallOptions(
                cacheMiss: true,
                flagName: BackendV2FeatureFlag.session.dottedName
            )
        )
        try value.validateContractVersion()
        return value
    }
}

/// Holds last Session Bootstrap for badge/following seeds (flag-ON path).
@MainActor
final class SessionBootstrapStore {
    static let shared = SessionBootstrapStore()

    private(set) var last: SessionBootstrapV1?
    private(set) var source: String?

    func seed(_ bootstrap: SessionBootstrapV1, source: String) {
        last = bootstrap
        self.source = source
    }

    func clear() {
        last = nil
        source = nil
    }
}

enum SessionBootstrapLoader {
    /// When `backendV2.session` is ON, load RPC and seed following IDs.
    /// Returns nil when flag is OFF (caller keeps existing REST path).
    static func loadIfEnabled(rpc: any RPCClient) async throws -> SessionBootstrapV1? {
        guard BackendV2FeatureFlags.isEnabled(.session) else { return nil }

        let repo = SessionRpcBootstrapRepository(rpc: rpc)
        let bootstrap = try await repo.loadSessionBootstrap()

        let viewerID = bootstrap.meta.viewer_id ?? bootstrap.data.viewer.id
        await SessionFollowingStore.shared.seed(
            viewerID: viewerID,
            ids: Set(bootstrap.data.following_ids)
        )

        await MainActor.run {
            SessionBootstrapStore.shared.seed(bootstrap, source: "rpc")
            #if DEBUG
            Logger(
                subsystem: "com.tradetraxs.TradeTraxs",
                category: "BackendV2"
            ).debug(
                "session bootstrap rpc following=\(bootstrap.data.following_ids.count) accounts=\(bootstrap.data.accounts_summary.count) notif=\(bootstrap.data.badges.notifications_unread) dm=\(bootstrap.data.badges.dm_unread)"
            )
            #endif
        }

        return bootstrap
    }
}
