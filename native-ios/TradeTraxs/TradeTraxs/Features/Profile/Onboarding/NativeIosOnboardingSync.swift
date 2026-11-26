import Foundation

@MainActor
enum NativeIosOnboardingServices {
    static var rpc: (any RPCClient)?
}

/// Server-backed native iOS onboarding state from session bootstrap (independent of web flags).
@MainActor
enum NativeIosOnboardingSessionStore {
    private(set) static var tourDismissedVersion: Int = 0
    private(set) static var planAcknowledged: Bool = false
    private(set) static var onboardingCompleted: Bool = false

    static func apply(session: SessionProfileV1) {
        tourDismissedVersion = session.ios_contextual_tour_dismissed_version ?? 0
        planAcknowledged = session.ios_post_onboarding_plan_acknowledged == true
        onboardingCompleted = session.onboarding_completed == true
    }

    static func noteMergedTourDismissedVersion(_ version: Int) {
        tourDismissedVersion = max(tourDismissedVersion, version)
    }

    static func notePlanAcknowledged() {
        planAcknowledged = true
    }

    static func reset() {
        tourDismissedVersion = 0
        planAcknowledged = false
        onboardingCompleted = false
    }
}

/// Merges local UserDefaults progress with server fields; uploads pending writes on reconnect.
@MainActor
enum NativeIosOnboardingSync {
    private static let pendingTourKeyPrefix = "tt.nativeIosOnboarding.pendingTour."
    private static let pendingPlanKeyPrefix = "tt.nativeIosOnboarding.pendingPlan."

    static func reconcile(session: SessionProfileV1, rpc: (any RPCClient)?) async {
        NativeIosOnboardingSessionStore.apply(session: session)
        let userID = session.id
        mergeTourDismissal(userID: userID, serverVersion: session.ios_contextual_tour_dismissed_version ?? 0)
        mergePlanAcknowledgment(
            userID: userID,
            serverAcknowledged: session.ios_post_onboarding_plan_acknowledged == true
        )
        await flushPending(userID: userID, rpc: rpc)
    }

    static func recordTourDismissed(userID: String, version: Int, rpc: (any RPCClient)?) {
        let store = ContextualTourProgressStore()
        store.dismiss(.dashboard, version: version, userID: userID)
        let pending = UserDefaults.standard.integer(forKey: pendingTourKey(userID))
        UserDefaults.standard.set(max(pending, version), forKey: pendingTourKey(userID))
        Task { await flushPending(userID: userID, rpc: rpc ?? NativeIosOnboardingServices.rpc) }
    }

    static func recordPlanAcknowledged(userID: String, rpc: (any RPCClient)?) {
        PostOnboardingPlanSelectionProgressStore().markCompleted(userID: userID)
        UserDefaults.standard.set(true, forKey: pendingPlanKey(userID))
        Task { await flushPending(userID: userID, rpc: rpc ?? NativeIosOnboardingServices.rpc) }
    }

    private static func mergeTourDismissal(userID: String, serverVersion: Int) {
        let store = ContextualTourProgressStore()
        let local = store.dismissedVersion(for: .dashboard, userID: userID)
        let merged = max(local, serverVersion)
        if merged > local {
            store.dismiss(.dashboard, version: merged, userID: userID)
        } else if local > serverVersion {
            let pending = UserDefaults.standard.integer(forKey: pendingTourKey(userID))
            UserDefaults.standard.set(max(pending, local), forKey: pendingTourKey(userID))
        }
        NativeIosOnboardingSessionStore.noteMergedTourDismissedVersion(merged)
    }

    private static func mergePlanAcknowledgment(userID: String, serverAcknowledged: Bool) {
        let local = PostOnboardingPlanSelectionProgressStore().hasCompleted(userID: userID)
        if serverAcknowledged {
            if !local {
                PostOnboardingPlanSelectionProgressStore().markCompleted(userID: userID)
            }
            NativeIosOnboardingSessionStore.notePlanAcknowledged()
        } else if local {
            UserDefaults.standard.set(true, forKey: pendingPlanKey(userID))
        }
    }

    private static func flushPending(userID: String, rpc: (any RPCClient)?) async {
        guard let rpc else { return }

        let pendingTour = UserDefaults.standard.integer(forKey: pendingTourKey(userID))
        if pendingTour > NativeIosOnboardingSessionStore.tourDismissedVersion {
            if await NativeIosOnboardingRpc.syncTourVersion(pendingTour, rpc: rpc) {
                UserDefaults.standard.removeObject(forKey: pendingTourKey(userID))
                NativeIosOnboardingSessionStore.noteMergedTourDismissedVersion(pendingTour)
            }
        }

        if UserDefaults.standard.bool(forKey: pendingPlanKey(userID)),
           !NativeIosOnboardingSessionStore.planAcknowledged
        {
            if await NativeIosOnboardingRpc.acknowledgePlan(rpc: rpc) {
                UserDefaults.standard.removeObject(forKey: pendingPlanKey(userID))
                NativeIosOnboardingSessionStore.notePlanAcknowledged()
            }
        }
    }

    private static func pendingTourKey(_ userID: String) -> String {
        pendingTourKeyPrefix + userID
    }

    private static func pendingPlanKey(_ userID: String) -> String {
        pendingPlanKeyPrefix + userID
    }
}

nonisolated enum NativeIosOnboardingRpc {
    private static let dismissName = "rpc_v1_ios_contextual_tour_dismiss"
    private static let syncName = "rpc_v1_ios_contextual_tour_sync"
    private static let planAckName = "rpc_v1_ios_post_onboarding_plan_acknowledge"

    static func syncTourVersion(_ version: Int, rpc: any RPCClient) async -> Bool {
        let body = try? JSONSerialization.data(withJSONObject: ["p_version": version])
        guard let body else { return false }
        if await callTourRPC(name: syncName, body: body, rpc: rpc) != nil {
            return true
        }
        return await callTourRPC(name: dismissName, body: body, rpc: rpc) != nil
    }

    private static func callTourRPC(name: String, body: Data, rpc: any RPCClient) async -> Int? {
        do {
            let data = try await rpc.call(functionName: name, jsonBody: body)
            if let value = try? JSONDecoder().decode(Int.self, from: data) {
                return value
            }
            if let number = try? JSONSerialization.jsonObject(with: data) as? Int {
                return number
            }
            return data.isEmpty ? 1 : nil
        } catch {
            return nil
        }
    }

    static func acknowledgePlan(rpc: any RPCClient) async -> Bool {
        do {
            _ = try await rpc.call(functionName: planAckName, jsonBody: Data("{}".utf8))
            return true
        } catch {
            return false
        }
    }
}