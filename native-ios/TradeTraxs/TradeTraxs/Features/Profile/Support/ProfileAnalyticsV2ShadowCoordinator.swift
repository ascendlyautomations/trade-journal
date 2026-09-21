import Foundation

/// Shadow-only Profile Analytics V2 fetch + parity (never mutates visible V1 stats).
enum ProfileAnalyticsV2ShadowCoordinator {
    struct Request: Sendable {
        var subjectProfileID: ProfileID
        var viewerScopeID: String
        var shadowGeneration: UInt64
        var v1CanViewStatistics: Bool
        var v1ModeResults: [ProfileStatisticsMetrics.Mode: ProfileStatisticsMetrics.Result]
        var force: Bool
    }

    static func schedule(
        rpc: any RPCClient,
        session: any SessionProviding,
        request: Request
    ) {
        guard BackendV2FeatureFlags.isEnabled(.profileAnalyticsV2Shadow) else { return }
        guard BackendV2FeatureFlags.isEnabled(.profile) else { return }

        let sessionKey =
            "\(request.shadowGeneration)|\(request.viewerScopeID)|\(request.subjectProfileID.rawValue)|shadow"

        Task(priority: .utility) {
            if !request.force {
                let began = await ProfileAnalyticsV2ShadowSession.shared.beginShadowSessionKey(sessionKey)
                guard began else { return }
            }

            await ProfileAnalyticsV2ShadowSession.shared.setActiveSubjectProfile(
                request.subjectProfileID.rawValue
            )

            let started = ContinuousClock.now
            #if DEBUG
            print(
                "[ProfileAnalyticsV2][ShadowStart] profile=\(request.subjectProfileID.rawValue) " +
                    "viewer=\(request.viewerScopeID)"
            )
            print("[ProfileAnalyticsV2][V1Ready] profile=\(request.subjectProfileID.rawValue)")
            #endif

            let capturedProfile = request.subjectProfileID
            let capturedGeneration = request.shadowGeneration
            let capturedViewer = request.viewerScopeID

            do {
                let v2Started = ContinuousClock.now
                async let bootstrapTask = ProfileAnalyticsV2BootstrapLoader.load(
                    viewerScopeID: capturedViewer,
                    profileID: capturedProfile,
                    rpc: rpc
                )
                async let revisionTask = ProfilePublicAnalyticsRevisionLoader.load(
                    viewerScopeID: capturedViewer,
                    profileID: capturedProfile,
                    rpc: rpc
                )

                let (bootstrap, revision) = try await (bootstrapTask, revisionTask)

                guard await isStillValid(
                    subjectProfileID: capturedProfile,
                    viewerScopeID: capturedViewer,
                    generation: capturedGeneration
                ) else {
                    #if DEBUG
                    print(
                        "[ProfileAnalyticsV2][StaleReject] profile=\(capturedProfile.rawValue) " +
                            "reason=session_or_navigation"
                    )
                    #endif
                    return
                }

                let v2Elapsed = v2Started.duration(to: ContinuousClock.now)
                #if DEBUG
                print(
                    "[ProfileAnalyticsV2][V2Ready] profile=\(capturedProfile.rawValue) " +
                        "bytes=\(bootstrap.encodedByteCount) elapsedMs=\(ms(v2Elapsed))"
                )
                print(
                    "[ProfileAnalyticsV2][Revision] profile=\(capturedProfile.rawValue) " +
                        "found=\(revision.payload.meta.found) revision=\(revision.payload.revisionInt ?? -1) " +
                        "bytes=\(revision.encodedByteCount)"
                )
                #endif

                let gate = ProfileAnalyticsV2Parity.compareGate(
                    v1CanViewStatistics: request.v1CanViewStatistics,
                    v2Found: bootstrap.applied.found
                )
                if !gate.matches {
                    #if DEBUG
                    print(
                        "[ProfileAnalyticsV2][Mismatch] profile=\(capturedProfile.rawValue) " +
                            "mode=gate field=visibility v1=\(gate.v1GateOpen) v2=\(gate.v2Found)"
                    )
                    #endif
                } else if request.v1CanViewStatistics {
                    let mismatches = ProfileAnalyticsV2Parity.compareModes(
                        profileID: capturedProfile,
                        v1: request.v1ModeResults,
                        v2: bootstrap.applied.modeResults
                    )
                    logParity(profileID: capturedProfile.rawValue, mismatches: mismatches)
                } else {
                    #if DEBUG
                    print(
                        "[ProfileAnalyticsV2][Parity] profile=\(capturedProfile.rawValue) " +
                            "mode=gate result=PASS locked"
                    )
                    #endif
                }

                let totalElapsed = started.duration(to: ContinuousClock.now)
                _ = totalElapsed
            } catch {
                guard !Task.isCancelled else { return }
                #if DEBUG
                print(
                    "[ProfileAnalyticsV2][ShadowError] profile=\(capturedProfile.rawValue) " +
                        "error=\(String(describing: error))"
                )
                #endif
            }
        }
    }

    static func viewerScopeID(session: any SessionProviding) async -> String {
        if let userID = await session.currentUserID {
            return userID.rawValue
        }
        return "anon"
    }

    private static func isStillValid(
        subjectProfileID: ProfileID,
        viewerScopeID: String,
        generation: UInt64
    ) async -> Bool {
        let currentGeneration = await ProfileAnalyticsV2ShadowSession.shared.currentGeneration()
        guard currentGeneration == generation else { return false }
        guard await ProfileAnalyticsV2ShadowSession.shared.isActiveSubjectProfile(subjectProfileID.rawValue)
        else { return false }
        _ = viewerScopeID
        return true
    }

    #if DEBUG
    private static func logParity(profileID: String, mismatches: [ProfileAnalyticsV2Parity.FieldMismatch]) {
        if mismatches.isEmpty {
            for mode in ProfileStatisticsMetrics.Mode.allCases {
                print(
                    "[ProfileAnalyticsV2][Parity] profile=\(profileID) mode=\(mode.rawValue) result=PASS"
                )
            }
            return
        }
        for mismatch in mismatches {
            print(
                "[ProfileAnalyticsV2][Mismatch] profile=\(profileID) mode=\(mismatch.mode.rawValue) " +
                    "field=\(mismatch.field) v1=\(mismatch.v1Value) v2=\(mismatch.v2Value) " +
                    "class=\(mismatch.classification.rawValue)"
            )
        }
    }
    #else
    private static func logParity(profileID: String, mismatches: [ProfileAnalyticsV2Parity.FieldMismatch]) {
        _ = profileID
        _ = mismatches
    }
    #endif

    private static func ms(_ duration: Duration) -> String {
        let nanos = duration.components.seconds * 1_000_000_000 + duration.components.attoseconds / 1_000_000_000
        return String(format: "%.2f", Double(nanos) / 1_000_000)
    }
}
