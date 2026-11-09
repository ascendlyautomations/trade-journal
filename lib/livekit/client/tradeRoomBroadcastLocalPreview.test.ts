import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { Track, type LocalVideoTrack } from "livekit-client"
import {
  attachLocalBroadcastVideoTrack,
  detachLocalBroadcastPreview,
  findLocalBroadcastProgramVideoPublication,
  findLocalBroadcastVideoPublication,
} from "./tradeRoomBroadcastLocalPreview.ts"

describe("tradeRoomBroadcastLocalPreview", () => {
  it("prefers camera publication for camera streams", () => {
    const room = {
      localParticipant: {
        videoTrackPublications: new Map([
          [
            "cam",
            {
              source: Track.Source.Camera,
              track: { sid: "cam" },
              videoTrack: { sid: "cam" },
            },
          ],
        ]),
      },
    } as never

    const pub = findLocalBroadcastVideoPublication(room, "camera")
    assert.equal(pub?.source, Track.Source.Camera)
  })

  it("program publication prefers live screen over camera", () => {
    const room = {
      localParticipant: {
        videoTrackPublications: new Map([
          [
            "cam",
            {
              source: Track.Source.Camera,
              track: {
                sid: "cam",
                mediaStreamTrack: { id: "cam", readyState: "live" },
              },
              videoTrack: {
                sid: "cam",
                mediaStreamTrack: { id: "cam", readyState: "live" },
              },
            },
          ],
          [
            "screen",
            {
              source: Track.Source.ScreenShare,
              track: {
                sid: "screen",
                mediaStreamTrack: { id: "screen", readyState: "live" },
              },
              videoTrack: {
                sid: "screen",
                mediaStreamTrack: { id: "screen", readyState: "live" },
              },
            },
          ],
        ]),
      },
    } as never

    const pub = findLocalBroadcastProgramVideoPublication(room)
    assert.equal(pub?.source, Track.Source.ScreenShare)
  })

  it("program publication falls back to camera when screen is not live", () => {
    const room = {
      localParticipant: {
        videoTrackPublications: new Map([
          [
            "cam",
            {
              source: Track.Source.Camera,
              track: {
                sid: "cam",
                mediaStreamTrack: { id: "cam", readyState: "live" },
              },
              videoTrack: {
                sid: "cam",
                mediaStreamTrack: { id: "cam", readyState: "live" },
              },
            },
          ],
          [
            "screen",
            {
              source: Track.Source.ScreenShare,
              track: {
                sid: "screen",
                mediaStreamTrack: { id: "screen", readyState: "ended" },
              },
            },
          ],
        ]),
      },
    } as never

    const pub = findLocalBroadcastProgramVideoPublication(room)
    assert.equal(pub?.source, Track.Source.Camera)
  })

  it("prefers screen-share publication for screen streams", () => {
    const room = {
      localParticipant: {
        videoTrackPublications: new Map([
          [
            "screen",
            {
              source: Track.Source.ScreenShare,
              track: { sid: "screen" },
              videoTrack: { sid: "screen" },
            },
          ],
        ]),
      },
    } as never

    const pub = findLocalBroadcastVideoPublication(room, "screen")
    assert.equal(pub?.source, Track.Source.ScreenShare)
  })
})

describe("attachLocalBroadcastVideoTrack — multi video element (panel + global chrome)", () => {
  it("does not detach the first element when the same track syncs to a second <video>", () => {
    detachLocalBroadcastPreview()

    const detachedFrom: unknown[] = []
    const sid = "cam-track-sid"
    const track = {
      sid,
      mediaStreamTrack: { id: sid },
      source: Track.Source.Camera,
      attach: (el: HTMLVideoElement) => {
        void el
      },
      detach: (el: HTMLVideoElement) => {
        detachedFrom.push(el)
      },
    } as unknown as LocalVideoTrack

    const el1 = { play: () => Promise.resolve() } as unknown as HTMLVideoElement
    const el2 = { play: () => Promise.resolve() } as unknown as HTMLVideoElement

    attachLocalBroadcastVideoTrack(track, el1)
    attachLocalBroadcastVideoTrack(track, el2)

    assert.deepEqual(
      detachedFrom,
      [],
      "same camera track shown in panel + studio must stay attached to both elements"
    )
  })

  it("does not detach the studio element when track.sid is assigned after the panel attach", () => {
    detachLocalBroadcastPreview()

    const detachedFrom: unknown[] = []
    const mediaId = "browser-media-stream-track-id"
    const track = {
      sid: undefined as string | undefined,
      mediaStreamTrack: { id: mediaId },
      source: Track.Source.Camera,
      attach: (el: HTMLVideoElement) => {
        void el
      },
      detach: (el: HTMLVideoElement) => {
        detachedFrom.push(el)
      },
    } as unknown as LocalVideoTrack

    const panel = { play: () => Promise.resolve() } as unknown as HTMLVideoElement
    const studio = { play: () => Promise.resolve() } as unknown as HTMLVideoElement

    attachLocalBroadcastVideoTrack(track, panel)
    track.sid = "LK_published_sid"
    attachLocalBroadcastVideoTrack(track, studio)

    assert.deepEqual(
      detachedFrom,
      [],
      "sid assignment after publish must not look like a new track and detach global studio"
    )
  })
})
