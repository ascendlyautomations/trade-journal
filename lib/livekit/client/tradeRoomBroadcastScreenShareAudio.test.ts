import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { describe, it } from "node:test"
import { Track } from "livekit-client"
import { shouldAttachRemoteBroadcastAudio } from "./tradeRoomBroadcastAudio.ts"
import { shouldRetryBrowserScreenShareWithoutAudio } from "./tradeRoomBroadcastScreenShareWhileLive.ts"

const hostId = "host-user"

function pub(source: Track.Source) {
  return { kind: Track.Kind.Audio, source } as never
}

function participant(identity: string) {
  return { identity } as never
}

describe("screen-share audio playback", () => {
  it("plays the broadcaster tab audio and ignores everyone else's", () => {
    const ctx = { broadcasterUserId: hostId, broadcastSource: "browser" as const }
    assert.equal(
      shouldAttachRemoteBroadcastAudio(ctx, participant(hostId), pub(Track.Source.ScreenShareAudio)),
      true
    )
    assert.equal(
      shouldAttachRemoteBroadcastAudio(
        ctx,
        participant("speaker-user"),
        pub(Track.Source.ScreenShareAudio)
      ),
      false
    )
  })

  it("still plays microphone and OBS program audio", () => {
    assert.equal(
      shouldAttachRemoteBroadcastAudio(
        { broadcasterUserId: hostId, broadcastSource: "browser" },
        participant("speaker-user"),
        pub(Track.Source.Microphone)
      ),
      true
    )
    assert.equal(
      shouldAttachRemoteBroadcastAudio(
        {
          broadcasterUserId: hostId,
          broadcastSource: "obs",
          primaryMediaPublisherIdentity: "ingress-1",
        },
        participant("ingress-1"),
        pub(Track.Source.ScreenShareAudio)
      ),
      true
    )
  })
})

describe("screen-share audio is optional", () => {
  it("retries without tab audio when capture or publish rejects it", () => {
    const unsupported = new Error("audio capture is not supported")
    unsupported.name = "NotSupportedError"
    assert.equal(shouldRetryBrowserScreenShareWithoutAudio(unsupported), true)
    assert.equal(
      shouldRetryBrowserScreenShareWithoutAudio(
        new Error("failed to publish track, insufficient permissions")
      ),
      true
    )
  })

  it("does not reopen the picker after the user cancels", () => {
    const cancelled = new Error("User cancelled screen share")
    assert.equal(shouldRetryBrowserScreenShareWithoutAudio(cancelled), false)
  })
})

describe("screen-share audio wiring", () => {
  it("requests tab audio on every browser share path and authorizes only the broadcaster", () => {
    const store = readFileSync(
      new URL("./tradeRoomBroadcastStore.ts", import.meta.url),
      "utf8"
    )
    assert.match(store, /const BROWSER_SCREEN_SHARE_OPTS = \{[\s\S]*?audio:\s*true/)
    assert.equal((store.match(/enableBrowserScreenShare\(/g) ?? []).length, 4)
    assert.equal((store.match(/audio:\s*false/g) ?? []).length, 1)

    const token = readFileSync(
      new URL("../mintLiveKitBroadcastToken.ts", import.meta.url),
      "utf8"
    )
    const publisher = token.slice(
      token.indexOf("export async function mintLiveKitBroadcastPublisherToken"),
      token.indexOf("export async function mintLiveKitBroadcastObsHostToken")
    )
    assert.match(publisher, /TrackSource\.SCREEN_SHARE_AUDIO/)
    const viewer = token.slice(
      token.indexOf("export async function mintLiveKitBroadcastViewerToken"),
      token.indexOf("export async function mintLiveKitBroadcastConversationToken")
    )
    assert.match(viewer, /canPublishSources:\s*\[\]/)
    assert.doesNotMatch(viewer, /SCREEN_SHARE_AUDIO/)
  })
})
