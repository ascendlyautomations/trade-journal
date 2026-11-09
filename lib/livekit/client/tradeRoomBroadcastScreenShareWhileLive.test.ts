import { describe, expect, it } from "vitest"
import {
  isBroadcastScreenShareCancelled,
  tradeRoomBroadcastScreenShareProgramActive,
  tradeRoomBroadcastShareScreenWhileLiveAvailable,
} from "./tradeRoomBroadcastScreenShareWhileLive.ts"

describe("isBroadcastScreenShareCancelled", () => {
  it("treats NotAllowedError as cancel", () => {
    expect(
      isBroadcastScreenShareCancelled(new DOMException("denied", "NotAllowedError"))
    ).toBe(true)
  })
  it("treats AbortError as cancel", () => {
    expect(
      isBroadcastScreenShareCancelled(new DOMException("abort", "AbortError"))
    ).toBe(true)
  })
})

describe("share screen while live availability", () => {
  const base = {
    isPublishing: true,
    role: "broadcaster" as const,
    status: {
      live: true,
      videoSource: "camera" as const,
      broadcastSource: "browser" as const,
    },
  }

  it("offers share when camera live on browser", () => {
    expect(tradeRoomBroadcastShareScreenWhileLiveAvailable(base)).toBe(true)
  })

  it("hides share for OBS", () => {
    expect(
      tradeRoomBroadcastShareScreenWhileLiveAvailable({
        ...base,
        status: { ...base.status, videoSource: "obs", broadcastSource: "obs" },
      })
    ).toBe(false)
  })

  it("screen program active when videoSource is screen", () => {
    expect(
      tradeRoomBroadcastScreenShareProgramActive({
        ...base,
        status: { ...base.status, videoSource: "screen" },
      })
    ).toBe(true)
  })
})
