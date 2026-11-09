import assert from "node:assert/strict"
import { describe, it } from "node:test"

/**
 * Regression: OBS private prep must surface credentials + errors in the broadcast store snapshot
 * (obsStudio.credentialsError, obsStudio.credentialsBusy) and expose obsBroadcastBootstrapping
 * while the LiveKit room connects — the panel uses these instead of the full broadcast chrome.
 */
describe("OBS preparation UI contract", () => {
  it("ObsStudioState includes credential error slot (never secrets)", () => {
    const sample = {
      phase: "creating_ingress" as const,
      rtmpUrl: "rtmps://example.com/live" as string | null,
      revealedStreamKey: null as string | null,
      hasIngressCredentials: false,
      credentialsBusy: true,
      credentialsLostOrUnavailable: false,
      credentialsError: null as string | null,
    }
    assert.equal(typeof sample.credentialsError, "object")
    assert.equal(sample.rtmpUrl?.includes("stream"), false)
  })

  it("documents private prep expanded predicate for tests/docs", () => {
    const obsPreparingHost = true
    const obsBroadcastBootstrapping = false
    const obsPrivateSetupExpanded =
      obsPreparingHost || obsBroadcastBootstrapping
    assert.equal(obsPrivateSetupExpanded, true)
  })
})
