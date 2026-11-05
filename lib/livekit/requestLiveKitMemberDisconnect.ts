/**
 * Browser-safe helper: asks BFF to remove a member from LiveKit voice rooms.
 * Database triggers also enqueue retries when LiveKit is unavailable.
 */
export async function requestLiveKitMemberDisconnect(options: {
  roomId: string
  userId: string
  accessToken: string
}): Promise<void> {
  if (typeof fetch === "undefined") return
  try {
    await fetch("/api/livekit/disconnect-member", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${options.accessToken}`,
      },
      body: JSON.stringify({
        roomId: options.roomId,
        userId: options.userId,
      }),
    })
  } catch (err) {
    console.warn("[livekit] disconnect-member request failed", err)
  }
}
