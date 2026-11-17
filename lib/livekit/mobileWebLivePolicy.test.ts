import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { describe, it } from "node:test"
import {
  BROADCAST_MEDIA_ATTR,
  BROADCAST_REMOTE_AUDIO_ROOT_ID,
  clientMayEnableGeneralVoiceMicrophone,
  generalVoiceMuteAllowsPublish,
  liveVoicePolicyShouldPauseMedia,
  shouldKeepBroadcastConnectionForConversation,
  shouldShowBroadcastEnableSound,
  shouldShowLiveVoicePlaybackUnlock,
  speakInviteAllowsMicrophone,
} from "./mobileWebLivePolicy.ts"

function source(relativePath: string): string {
  return readFileSync(new URL(relativePath, import.meta.url), "utf8")
}

function sliceExport(src: string, name: string, nextName: string): string {
  const start = src.indexOf(name)
  const end = src.indexOf(nextName, start + name.length)
  assert.ok(start !== -1, `missing ${name}`)
  assert.ok(end !== -1, `missing ${nextName} after ${name}`)
  return src.slice(start, end)
}

describe("mobile web live P0 policy", () => {
  it("shows General Voice unlock whenever playback is blocked, including an active session", () => {
    assert.equal(
      shouldShowLiveVoicePlaybackUnlock({
        hasSession: true,
        canPlaybackAudio: false,
      }),
      true
    )
    assert.equal(
      shouldShowLiveVoicePlaybackUnlock({
        hasSession: true,
        canPlaybackAudio: true,
      }),
      false
    )
    assert.equal(
      shouldShowLiveVoicePlaybackUnlock({
        hasSession: false,
        canPlaybackAudio: false,
      }),
      false
    )
  })

  it("starts LiveKit audio in the join function before the first await", () => {
    const voice = source("./client/tradeRoomLiveVoiceStore.ts")
    const join = sliceExport(
      voice,
      "export async function joinTradeRoomLiveVoice",
      "export async function resumeTradeRoomLiveVoicePlayback"
    )
    const audioAt = join.indexOf("startAudio(")
    const awaitAt = join.indexOf("await ")
    assert.ok(audioAt !== -1)
    assert.ok(awaitAt !== -1)
    assert.ok(audioAt < awaitAt)
  })

  it("unlocks broadcast audio from Watch before the viewer token request", () => {
    const store = source("./client/tradeRoomBroadcastStore.ts")
    const watch = sliceExport(
      store,
      "export async function watchTradeRoomBroadcast",
      "export async function joinTradeRoomBroadcastConversation"
    )
    const unlockAt = watch.indexOf("beginBroadcastAudioUnlock(")
    const fetchAt = watch.indexOf("await options.fetchViewerToken")
    assert.ok(unlockAt !== -1)
    assert.ok(fetchAt !== -1)
    assert.ok(unlockAt < fetchAt)

    const unlockFn = sliceExport(
      store,
      "function beginBroadcastAudioUnlock",
      "export function resumeTradeRoomBroadcastPlayback"
    )
    const audioAt = unlockFn.indexOf("startAudio(")
    const awaitAt = unlockFn.indexOf("await ")
    assert.ok(audioAt !== -1)
    if (awaitAt !== -1) assert.ok(audioAt < awaitAt)
  })

  it("shows Enable sound for a watching viewer whose playback is blocked", () => {
    assert.equal(
      shouldShowBroadcastEnableSound({
        isWatching: true,
        isPublishing: false,
        canPlaybackAudio: false,
      }),
      true
    )
    assert.equal(
      shouldShowBroadcastEnableSound({
        isWatching: true,
        isPublishing: false,
        canPlaybackAudio: true,
      }),
      false
    )
    assert.equal(
      shouldShowBroadcastEnableSound({
        isWatching: false,
        isPublishing: true,
        canPlaybackAudio: false,
      }),
      false
    )
  })

  it("keeps the LiveKit room across conversation changes on the same broadcast", () => {
    assert.equal(
      shouldKeepBroadcastConnectionForConversation({
        connected: true,
        sameRoom: true,
        sameSession: true,
      }),
      true
    )
    assert.equal(
      shouldKeepBroadcastConnectionForConversation({
        connected: true,
        sameRoom: false,
        sameSession: true,
      }),
      false
    )
    assert.equal(
      shouldKeepBroadcastConnectionForConversation({
        connected: false,
        sameRoom: true,
        sameSession: true,
      }),
      false
    )
  })

  it("revokes General Voice publish on mute and blocks client unmute while restricted", () => {
    assert.equal(generalVoiceMuteAllowsPublish(true), false)
    assert.equal(generalVoiceMuteAllowsPublish(false), true)
    assert.equal(
      clientMayEnableGeneralVoiceMicrophone({
        joinedWithPublish: true,
        liveKitCanPublish: false,
      }),
      false
    )
    assert.equal(
      clientMayEnableGeneralVoiceMicrophone({
        joinedWithPublish: true,
        liveKitCanPublish: true,
      }),
      true
    )
    assert.equal(
      clientMayEnableGeneralVoiceMicrophone({
        joinedWithPublish: false,
        liveKitCanPublish: true,
      }),
      false
    )

    const server = source("./liveKitRoomService.ts")
    const muteFn = sliceExport(
      server,
      "export async function muteLiveKitGeneralVoiceParticipantMicrophone",
      "export async function disconnectUserFromTradeRoomLiveKit"
    )
    assert.match(muteFn, /generalVoiceMuteAllowsPublish/)
    assert.match(muteFn, /updateParticipant/)
    assert.match(muteFn, /canPublishSources/)
  })

  it("does not enable a microphone unless the speak invite was accepted", () => {
    assert.equal(speakInviteAllowsMicrophone({ accepted: false }), false)
    assert.equal(speakInviteAllowsMicrophone({ accepted: true }), true)

    const store = source("./client/tradeRoomBroadcastStore.ts")
    assert.equal(store.includes("maybeAutoUpgradeViewerToSpeaker"), false)
    const dismiss = sliceExport(
      store,
      "export function dismissTradeRoomBroadcastSpeakInvite",
      "export async function declineTradeRoomBroadcastSpeakInvite"
    )
    assert.equal(dismiss.includes("setMicrophoneEnabled"), false)
    assert.equal(dismiss.includes("speakInviteAllowsMicrophone"), false)
  })

  it("does not pause broadcast media when General Voice connects", () => {
    const broadcastAudio = {
      getAttribute: () => null,
      closest: (selector: string) =>
        selector.includes(BROADCAST_REMOTE_AUDIO_ROOT_ID) ? {} : null,
    }
    const broadcastVideo = {
      getAttribute: (name: string) =>
        name === BROADCAST_MEDIA_ATTR ? "true" : null,
      closest: () => null,
    }
    const clip = {
      getAttribute: () => null,
      closest: () => null,
    }
    assert.equal(liveVoicePolicyShouldPauseMedia(broadcastAudio), false)
    assert.equal(liveVoicePolicyShouldPauseMedia(broadcastVideo), false)
    assert.equal(liveVoicePolicyShouldPauseMedia(clip), true)
  })
})
