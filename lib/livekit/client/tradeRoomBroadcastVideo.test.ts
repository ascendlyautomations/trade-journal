import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  findBrowserBroadcasterProgramVideoPublication,
  findObsProgramVideoPublication,
  isBroadcastCameraPublication,
  isBroadcastScreenSharePublication,
  obsPrimaryPublicationMatches,
} from "./tradeRoomBroadcastVideo.ts"
import { Track } from "livekit-client"

describe("tradeRoomBroadcastVideo — track source classification", () => {
  it("identifies screen-share vs camera publications", () => {
    assert.equal(
      isBroadcastScreenSharePublication({
        source: Track.Source.ScreenShare,
      } as never),
      true
    )
    assert.equal(
      isBroadcastCameraPublication({
        source: Track.Source.Camera,
      } as never),
      true
    )
    assert.equal(
      isBroadcastScreenSharePublication({
        source: Track.Source.Camera,
      } as never),
      false
    )
  })
})

describe("findBrowserBroadcasterProgramVideoPublication", () => {
  const hostId = "host-user"

  function fakeRoomWithHostPubs(
    pubs: Array<{ source: Track.Source; sid: string }>
  ) {
    const m = new Map<string, { kind: Track.Kind; source: Track.Source; track: unknown; trackSid: string; isSubscribed: boolean }>()
    pubs.forEach((p, i) => {
      m.set(`pub-${i}`, {
        kind: Track.Kind.Video,
        source: p.source,
        trackSid: p.sid,
        isSubscribed: true,
        track: { sid: p.sid, mediaStreamTrack: { id: p.sid } },
      })
    })
    return {
      remoteParticipants: new Map([
        [
          hostId,
          {
            identity: hostId,
            videoTrackPublications: m,
          },
        ],
      ]),
    } as import("livekit-client").Room
  }

  it("prefers screen over camera when both are published (mid-stream share)", () => {
    const room = fakeRoomWithHostPubs([
      { source: Track.Source.Camera, sid: "cam-1" },
      { source: Track.Source.ScreenShare, sid: "screen-1" },
    ])
    const pub = findBrowserBroadcasterProgramVideoPublication(room, hostId)
    assert.equal(pub?.source, Track.Source.ScreenShare)
  })

  it("returns camera when screen is unpublished (after stop sharing)", () => {
    const room = fakeRoomWithHostPubs([
      { source: Track.Source.Camera, sid: "cam-2" },
    ])
    const pub = findBrowserBroadcasterProgramVideoPublication(room, hostId)
    assert.equal(pub?.source, Track.Source.Camera)
  })
})

describe("findObsProgramVideoPublication", () => {
  const programId = "tt-obs-sess-1"

  function fakeRoomWithPubs(
    pubs: Array<{ source: Track.Source; kind: Track.Kind }>
  ) {
    const m = new Map<string, { kind: Track.Kind; source: Track.Source; track: unknown }>()
    pubs.forEach((p, i) => {
      const sid = `mock-track-${i}`
      m.set(`pub-${i}`, {
        kind: p.kind,
        source: p.source,
        track: { sid, mediaStreamTrack: { id: sid } },
      })
    })
    return {
      remoteParticipants: new Map([
        [
          programId,
          {
            identity: programId,
            videoTrackPublications: m,
          },
        ],
      ]),
    } as import("livekit-client").Room
  }

  it("prefers screen_share over camera when both exist on ingress participant", () => {
    const room = fakeRoomWithPubs([
      { kind: Track.Kind.Video, source: Track.Source.Camera },
      { kind: Track.Kind.Video, source: Track.Source.ScreenShare },
    ])
    const pub = findObsProgramVideoPublication(room, programId)
    assert.equal(pub?.source, Track.Source.ScreenShare)
  })

  it("prefers unknown/non-camera source over camera (duplicate ingress tracks)", () => {
    const room = fakeRoomWithPubs([
      { kind: Track.Kind.Video, source: Track.Source.Camera },
      { kind: Track.Kind.Video, source: Track.Source.Unknown },
    ])
    const pub = findObsProgramVideoPublication(room, programId)
    assert.equal(pub?.source, Track.Source.Unknown)
  })

  it("falls back to camera when it is the only video", () => {
    const room = fakeRoomWithPubs([
      { kind: Track.Kind.Video, source: Track.Source.Camera },
    ])
    const pub = findObsProgramVideoPublication(room, programId)
    assert.equal(pub?.source, Track.Source.Camera)
  })

  it("obsPrimaryPublicationMatches prefers screen over camera when both exist", () => {
    const room = fakeRoomWithPubs([
      { kind: Track.Kind.Video, source: Track.Source.Camera },
      { kind: Track.Kind.Video, source: Track.Source.ScreenShare },
    ])
    const participant = room.remoteParticipants.get(programId) as {
      videoTrackPublications: Map<string, { source: Track.Source }>
    }
    const pubs = [...participant.videoTrackPublications.values()]
    const camPub = pubs.find((p) => p.source === Track.Source.Camera)
    const screenPub = pubs.find((p) => p.source === Track.Source.ScreenShare)
    assert.equal(obsPrimaryPublicationMatches(room, programId, camPub as never), false)
    assert.equal(obsPrimaryPublicationMatches(room, programId, screenPub as never), true)
  })
})
