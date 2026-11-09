import assert from "node:assert/strict"
import { describe, it } from "node:test"
import type { BroadcastStoreSnapshot } from "./tradeRoomBroadcastStore.ts"
import { tradeRoomBroadcastGlobalChromeVisible } from "./tradeRoomBroadcastGlobalChromeVisibility.ts"

const sessionA = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
const sessionB = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"

function slice(
  snap: Partial<
    Pick<
      BroadcastStoreSnapshot,
      | "isPublishing"
      | "isWatching"
      | "role"
      | "studioPresentation"
      | "status"
      | "publisherSessionId"
      | "obsHostUiPhase"
      | "obsBroadcastBootstrapping"
    >
  > &
    Pick<BroadcastStoreSnapshot, "role" | "studioPresentation" | "status">
) {
  return {
    isPublishing: false,
    isWatching: false,
    publisherSessionId: null,
    obsHostUiPhase: null,
    obsBroadcastBootstrapping: false,
    ...snap,
  }
}

const viewerPublicBase = {
  isPublishing: false,
  isWatching: true,
  role: "viewer" as const,
  studioPresentation: "studio" as const,
  publisherSessionId: null,
  obsHostUiPhase: null,
  obsBroadcastBootstrapping: false,
  status: {
    live: true,
    broadcastSessionId: sessionA,
    publicLive: true,
    visibility: "public" as const,
  },
}

describe("TradeRoomBroadcastGlobalChrome visibility (component gate)", () => {
  it("1. OBS preparing + isPublishing + studio presentation → hidden", () => {
    assert.equal(
      tradeRoomBroadcastGlobalChromeVisible(
        slice({
          isPublishing: true,
          role: "broadcaster",
          studioPresentation: "studio",
          publisherSessionId: sessionA,
          obsHostUiPhase: "preparing",
          obsBroadcastBootstrapping: false,
          status: {
            live: true,
            broadcastSessionId: sessionA,
            videoSource: "obs",
            broadcastSource: "obs",
            publicLive: false,
            visibility: "preparing",
          },
        })
      ),
      false
    )
  })

  it("2. OBS credentials loading → hidden", () => {
    assert.equal(
      tradeRoomBroadcastGlobalChromeVisible(
        slice({
          isPublishing: true,
          role: "broadcaster",
          studioPresentation: "studio",
          publisherSessionId: sessionA,
          obsHostUiPhase: "preparing",
          obsBroadcastBootstrapping: false,
          status: {
            live: true,
            broadcastSessionId: sessionA,
            videoSource: "obs",
            broadcastSource: "obs",
            publicLive: false,
            visibility: "preparing",
          },
        })
      ),
      false
    )
  })

  it("3. OBS credential error → hidden", () => {
    assert.equal(
      tradeRoomBroadcastGlobalChromeVisible(
        slice({
          isPublishing: true,
          role: "broadcaster",
          studioPresentation: "studio",
          publisherSessionId: sessionA,
          obsHostUiPhase: "error",
          obsBroadcastBootstrapping: false,
          status: {
            live: true,
            broadcastSessionId: sessionA,
            videoSource: "obs",
            broadcastSource: "obs",
            publicLive: false,
            visibility: "preparing",
          },
        })
      ),
      false
    )
  })

  it("4. OBS private preview ready → hidden", () => {
    assert.equal(
      tradeRoomBroadcastGlobalChromeVisible(
        slice({
          isPublishing: true,
          role: "broadcaster",
          studioPresentation: "studio",
          publisherSessionId: sessionA,
          obsHostUiPhase: "preview_ready",
          obsBroadcastBootstrapping: false,
          status: {
            live: true,
            broadcastSessionId: sessionA,
            videoSource: "obs",
            broadcastSource: "obs",
            publicLive: false,
            visibility: "preparing",
          },
        })
      ),
      false
    )
  })

  it("5. OBS publish in progress → hidden", () => {
    assert.equal(
      tradeRoomBroadcastGlobalChromeVisible(
        slice({
          isPublishing: true,
          role: "broadcaster",
          studioPresentation: "studio",
          publisherSessionId: sessionA,
          obsHostUiPhase: "publishing",
          obsBroadcastBootstrapping: false,
          status: {
            live: true,
            broadcastSessionId: sessionA,
            videoSource: "obs",
            broadcastSource: "obs",
            publicLive: false,
            visibility: "preparing",
          },
        })
      ),
      false
    )
  })

  it("6. OBS publicLive true for matching session + public phase → visible", () => {
    assert.equal(
      tradeRoomBroadcastGlobalChromeVisible(
        slice({
          isPublishing: true,
          role: "broadcaster",
          studioPresentation: "studio",
          publisherSessionId: sessionA,
          obsHostUiPhase: "public",
          obsBroadcastBootstrapping: false,
          status: {
            live: true,
            broadcastSessionId: sessionA,
            videoSource: "obs",
            broadcastSource: "obs",
            publicLive: true,
            visibility: "public",
          },
        })
      ),
      true
    )
  })

  it("7. Browser screen share public → visible", () => {
    assert.equal(
      tradeRoomBroadcastGlobalChromeVisible(
        slice({
          isPublishing: true,
          role: "broadcaster",
          studioPresentation: "studio",
          publisherSessionId: sessionA,
          obsHostUiPhase: null,
          obsBroadcastBootstrapping: false,
          status: {
            live: true,
            broadcastSessionId: sessionA,
            videoSource: "screen",
            publicLive: true,
            visibility: "public",
          },
        })
      ),
      true
    )
  })

  it("8. Camera public → visible", () => {
    assert.equal(
      tradeRoomBroadcastGlobalChromeVisible(
        slice({
          isPublishing: true,
          role: "broadcaster",
          studioPresentation: "studio",
          publisherSessionId: sessionA,
          obsHostUiPhase: null,
          obsBroadcastBootstrapping: false,
          status: {
            live: true,
            broadcastSessionId: sessionA,
            videoSource: "camera",
            publicLive: true,
            visibility: "public",
          },
        })
      ),
      true
    )
  })

  it("9. OBS with missing/null visibility in client status → hidden even if publicLive true", () => {
    assert.equal(
      tradeRoomBroadcastGlobalChromeVisible(
        slice({
          isPublishing: true,
          role: "broadcaster",
          studioPresentation: "studio",
          publisherSessionId: sessionA,
          obsHostUiPhase: "public",
          obsBroadcastBootstrapping: false,
          status: {
            live: true,
            broadcastSessionId: sessionA,
            videoSource: "obs",
            broadcastSource: "obs",
            publicLive: true,
            visibility: undefined,
          },
        })
      ),
      false
    )
  })

  it("10. Stale status from different session → hidden", () => {
    assert.equal(
      tradeRoomBroadcastGlobalChromeVisible(
        slice({
          isPublishing: true,
          role: "broadcaster",
          studioPresentation: "studio",
          publisherSessionId: sessionA,
          obsHostUiPhase: null,
          obsBroadcastBootstrapping: false,
          status: {
            live: true,
            broadcastSessionId: sessionB,
            videoSource: "obs",
            broadcastSource: "obs",
            publicLive: true,
            visibility: "public",
          },
        })
      ),
      false
    )
  })

  it("11. Viewer watching public live + studio presentation → visible", () => {
    assert.equal(
      tradeRoomBroadcastGlobalChromeVisible(slice(viewerPublicBase)),
      true
    )
  })

  it("12. Viewer studio hidden → hidden", () => {
    assert.equal(
      tradeRoomBroadcastGlobalChromeVisible(
        slice({ ...viewerPublicBase, studioPresentation: "hidden" })
      ),
      false
    )
  })
})
