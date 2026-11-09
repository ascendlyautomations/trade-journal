import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  resolveBroadcastGlobalStudioVisible,
  resolveBroadcastViewerChromeVisible,
} from "./broadcastGlobalStudioVisibility.ts"

const sessionA = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
const sessionB = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"

describe("resolveBroadcastGlobalStudioVisible", () => {
  const browserPublicBase = {
    isPublishing: true,
    role: "broadcaster" as const,
    studioPresentation: "studio" as const,
    publisherSessionId: sessionA,
    obsHostUiPhase: null,
    obsBroadcastBootstrapping: false,
    status: {
      live: true,
      broadcastSessionId: sessionA,
      videoSource: "screen" as const,
      publicLive: true,
      visibility: "public" as const,
    },
  }

  it("shows browser screen share when publishing with studio presentation (legacy public)", () => {
    assert.equal(resolveBroadcastGlobalStudioVisible(browserPublicBase), true)
  })

  it("shows browser camera public the same way", () => {
    assert.equal(
      resolveBroadcastGlobalStudioVisible({
        ...browserPublicBase,
        status: {
          ...browserPublicBase.status,
          videoSource: "camera",
        },
      }),
      true
    )
  })

  it("keeps chrome visible for active publisher when status session is stale", () => {
    assert.equal(
      resolveBroadcastGlobalStudioVisible({
        ...browserPublicBase,
        status: {
          ...browserPublicBase.status,
          broadcastSessionId: sessionB,
        },
      }),
      true
    )
  })

  it("OBS preparing + studio presentation: hidden", () => {
    assert.equal(
      resolveBroadcastGlobalStudioVisible({
        ...browserPublicBase,
        status: {
          live: true,
          broadcastSessionId: sessionA,
          videoSource: "obs",
          broadcastSource: "obs",
          publicLive: false,
          visibility: "preparing",
        },
        obsHostUiPhase: "preparing",
      }),
      false
    )
  })

  it("OBS credentials loading (bootstrapping): hidden", () => {
    assert.equal(
      resolveBroadcastGlobalStudioVisible({
        ...browserPublicBase,
        status: {
          live: true,
          broadcastSessionId: sessionA,
          videoSource: "obs",
          broadcastSource: "obs",
          publicLive: false,
          visibility: "preparing",
        },
        obsBroadcastBootstrapping: true,
        obsHostUiPhase: "preparing",
      }),
      false
    )
  })

  it("OBS credential error phase: hidden", () => {
    assert.equal(
      resolveBroadcastGlobalStudioVisible({
        ...browserPublicBase,
        status: {
          live: true,
          broadcastSessionId: sessionA,
          videoSource: "obs",
          broadcastSource: "obs",
          publicLive: false,
          visibility: "preparing",
        },
        obsHostUiPhase: "error",
      }),
      false
    )
  })

  it("OBS waiting for encoder: hidden", () => {
    assert.equal(
      resolveBroadcastGlobalStudioVisible({
        ...browserPublicBase,
        status: {
          live: true,
          broadcastSessionId: sessionA,
          videoSource: "obs",
          broadcastSource: "obs",
          publicLive: false,
          visibility: "preparing",
        },
        obsHostUiPhase: "waiting_for_encoder",
      }),
      false
    )
  })

  it("OBS private preview ready: hidden", () => {
    assert.equal(
      resolveBroadcastGlobalStudioVisible({
        ...browserPublicBase,
        status: {
          live: true,
          broadcastSessionId: sessionA,
          videoSource: "obs",
          broadcastSource: "obs",
          publicLive: false,
          visibility: "preparing",
        },
        obsHostUiPhase: "preview_ready",
      }),
      false
    )
  })

  it("OBS publish in flight: hidden", () => {
    assert.equal(
      resolveBroadcastGlobalStudioVisible({
        ...browserPublicBase,
        status: {
          live: true,
          broadcastSessionId: sessionA,
          videoSource: "obs",
          broadcastSource: "obs",
          publicLive: false,
          visibility: "preparing",
        },
        obsHostUiPhase: "publishing",
      }),
      false
    )
  })

  it("OBS explicit public for matching session + public phase: visible", () => {
    assert.equal(
      resolveBroadcastGlobalStudioVisible({
        ...browserPublicBase,
        status: {
          live: true,
          broadcastSessionId: sessionA,
          videoSource: "obs",
          broadcastSource: "obs",
          publicLive: true,
          visibility: "public",
        },
        obsHostUiPhase: "public",
      }),
      true
    )
  })

  it("OBS with null/missing visibility in status cannot be public (server merge must set preparing)", () => {
    assert.equal(
      resolveBroadcastGlobalStudioVisible({
        ...browserPublicBase,
        status: {
          live: true,
          broadcastSessionId: sessionA,
          videoSource: "obs",
          broadcastSource: "obs",
          publicLive: true,
          visibility: undefined,
        },
        obsHostUiPhase: "public",
      }),
      false
    )
  })

  it("viewer watching with mini presentation is visible", () => {
    assert.equal(
      resolveBroadcastViewerChromeVisible({
        isWatching: true,
        role: "viewer",
        studioPresentation: "mini",
        status: {
          live: true,
          broadcastSessionId: sessionA,
          publicLive: true,
          visibility: "public",
        },
      }),
      true
    )
  })

  it("viewer with hidden presentation is hidden", () => {
    assert.equal(
      resolveBroadcastViewerChromeVisible({
        isWatching: true,
        role: "viewer",
        studioPresentation: "hidden",
        status: {
          live: true,
          broadcastSessionId: sessionA,
          publicLive: true,
          visibility: "public",
        },
      }),
      false
    )
  })

  it("OBS without publisher session id: hidden", () => {
    assert.equal(
      resolveBroadcastGlobalStudioVisible({
        ...browserPublicBase,
        publisherSessionId: null,
        status: {
          live: true,
          broadcastSessionId: sessionA,
          videoSource: "obs",
          broadcastSource: "obs",
          publicLive: true,
          visibility: "public",
        },
        obsHostUiPhase: "public",
      }),
      false
    )
  })
})
