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

export function broadcastStartErrorMessage(err: unknown): string {
  if (err instanceof Error) {
    const name = err.name
    const msg = err.message.toLowerCase()
    if (
      name === "NotAllowedError" ||
      msg.includes("permission") ||
      msg.includes("permissions policy")
    ) {
      if (
        msg.includes("camera") ||
        msg.includes("video") ||
        msg.includes("permissions policy")
      ) {
        return "Camera access was blocked. Allow camera for this site in your browser settings, then reload the page."
      }
      if (msg.includes("microphone") || msg.includes("audio")) {
        return "Microphone access was blocked."
      }
      return "Screen sharing was blocked. Allow screen capture in your browser settings."
    }
    if (name === "NotFoundError" || msg.includes("cancel")) {
      return "Sharing was cancelled."
    }
    if (msg.includes("not supported")) {
      return "This capture source is not supported in this browser."
    }
    return err.message
  }
  return "Could not start the live stream."
}
