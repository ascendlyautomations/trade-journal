export function broadcastStartErrorMessageForTest(err: unknown): string {
  return broadcastStartErrorMessage(err)
}

export function broadcastStartErrorMessage(err: unknown): string {
  if (err instanceof Error) {
    const name = err.name
    const msg = err.message.toLowerCase()
    if (name === "NotAllowedError" || msg.includes("permission")) {
      if (msg.includes("camera") || msg.includes("video")) {
        return "Camera access was blocked. Allow camera in your browser settings."
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
