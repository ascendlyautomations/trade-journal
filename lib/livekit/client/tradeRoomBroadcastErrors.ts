import {
  BroadcastCapturePreflightError,
} from "./tradeRoomBroadcastCapturePermissions.ts"
import type { TradeRoomBroadcastVideoSource } from "@/lib/livekit/tradeRoomBroadcastVoiceMode.ts"

export function broadcastStartErrorMessageForTest(err: unknown): string {
  return broadcastStartErrorMessage(err)
}

/** Thrown when the viewer token API returns no active stream (e.g. 404) — not a user-facing failure. */
export class BroadcastNoActiveStreamError extends Error {
  override name = "BroadcastNoActiveStreamError"
  constructor(message = "No live stream is active in this room.") {
    super(message)
    Object.setPrototypeOf(this, new.target.prototype)
  }
}

export function broadcastCaptureErrorMessage(
  err: unknown,
  videoSource?: TradeRoomBroadcastVideoSource | null
): string {
  if (err instanceof BroadcastCapturePreflightError) {
    return err.message
  }
  if (err instanceof Error) {
    const name = err.name
    const msg = err.message.toLowerCase()
    if (
      name === "NotAllowedError" ||
      msg.includes("permission") ||
      msg.includes("permissions policy")
    ) {
      const treatAsCamera =
        videoSource === "camera" ||
        (videoSource !== "screen" &&
          (msg.includes("camera") ||
            msg.includes("video") ||
            msg.includes("permissions policy")))
      if (treatAsCamera) {
        return "Camera access was blocked. Allow camera for this site in your browser settings, then use Retry."
      }
      if (msg.includes("microphone") || msg.includes("audio")) {
        return "Microphone access was blocked. Allow microphone for this site in your browser settings, then use Retry."
      }
      if (videoSource === "screen" || msg.includes("display")) {
        return "Screen sharing was blocked. Allow screen capture in your browser settings. On macOS, enable Screen Recording for your browser under System Settings → Privacy & Security, then use Retry."
      }
      return "Capture was blocked. Check browser permissions for this site, then use Retry."
    }
    if (name === "NotFoundError" || msg.includes("cancel")) {
      return videoSource === "camera"
        ? "Camera sharing was cancelled. Choose Retry to try again."
        : "Screen sharing was cancelled. Choose Retry to pick a screen, window, or tab."
    }
    if (msg.includes("not supported")) {
      return "This capture source is not supported in this browser."
    }
    return err.message
  }
  return "Could not start the live stream."
}

export function broadcastStartErrorMessage(err: unknown): string {
  return broadcastCaptureErrorMessage(err, null)
}
