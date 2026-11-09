import {
  hasGetUserMediaSupport,
  isSecureRecordingContext,
} from "../../microphoneAccess.ts"
import type { TradeRoomBroadcastVideoSource } from "../tradeRoomBroadcastVoiceMode.ts"

export class BroadcastCapturePreflightError extends Error {
  override name = "BroadcastCapturePreflightError"
  constructor(message: string) {
    super(message)
    Object.setPrototypeOf(this, new.target.prototype)
  }
}

function hasGetDisplayMediaSupport(): boolean {
  return (
    typeof navigator !== "undefined" &&
    typeof navigator.mediaDevices?.getDisplayMedia === "function"
  )
}

type MediaPermissionState = PermissionState | "unknown"

async function queryMediaPermission(
  name: "camera" | "microphone" | "display-capture"
): Promise<MediaPermissionState> {
  if (typeof navigator === "undefined" || !navigator.permissions?.query) {
    return "unknown"
  }
  try {
    const status = await navigator.permissions.query({
      name: name as PermissionName,
    })
    return status.state
  } catch {
    return "unknown"
  }
}

const CAMERA_BLOCKED_COPY =
  "Camera access is blocked. Allow camera for this site in your browser settings (click the lock or site icon in the address bar), then use Retry."

const MICROPHONE_BLOCKED_COPY =
  "Microphone access is blocked. Allow microphone for this site in your browser settings, then use Retry."

const SCREEN_BLOCKED_COPY =
  "Screen sharing is blocked. Allow screen capture for this site in your browser settings. On macOS, also enable Screen Recording for your browser under System Settings → Privacy & Security, then use Retry."

/**
 * Checks capture prerequisites where the Permissions API can tell us access is
 * already denied — avoids repeated getUserMedia prompts until the user fixes settings.
 * Does not request capture; LiveKit / getDisplayMedia still show normal prompts when allowed.
 */
export async function assertTradeRoomBroadcastCapturePreflight(
  videoSource: TradeRoomBroadcastVideoSource,
  options: { includeMicrophone?: boolean } = {}
): Promise<void> {
  if (videoSource === "obs") return

  if (!isSecureRecordingContext()) {
    throw new BroadcastCapturePreflightError(
      "Live streaming requires a secure (HTTPS) connection in this browser."
    )
  }

  if (videoSource === "camera") {
    if (!hasGetUserMediaSupport()) {
      throw new BroadcastCapturePreflightError(
        "Camera capture is not supported in this browser."
      )
    }
    const camera = await queryMediaPermission("camera")
    if (camera === "denied") {
      throw new BroadcastCapturePreflightError(CAMERA_BLOCKED_COPY)
    }
    if (options.includeMicrophone) {
      const mic = await queryMediaPermission("microphone")
      if (mic === "denied") {
        throw new BroadcastCapturePreflightError(MICROPHONE_BLOCKED_COPY)
      }
    }
    return
  }

  if (videoSource === "screen") {
    if (!hasGetDisplayMediaSupport()) {
      throw new BroadcastCapturePreflightError(
        "Screen sharing is not supported in this browser."
      )
    }
    const display = await queryMediaPermission("display-capture")
    if (display === "denied") {
      throw new BroadcastCapturePreflightError(SCREEN_BLOCKED_COPY)
    }
  }
}

export function isRecoverableBroadcastCaptureError(err: unknown): boolean {
  if (err instanceof BroadcastCapturePreflightError) return true
  if (!(err instanceof Error)) {
    const msg = String(err ?? "").toLowerCase()
    return (
      msg.includes("cancel") ||
      msg.includes("not published") ||
      msg.includes("not started")
    )
  }
  const name = err.name
  const msg = err.message.toLowerCase()
  if (name === "NotAllowedError" || name === "PermissionDeniedError") {
    return true
  }
  if (name === "NotFoundError" || msg.includes("cancel")) {
    return true
  }
  if (
    msg.includes("screen share was cancelled") ||
    msg.includes("camera track was not published") ||
    msg.includes("no video track was published")
  ) {
    return true
  }
  return false
}
