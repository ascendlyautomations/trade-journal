"use client"

type PublisherCredentials = {
  roomId: string
  sessionId: string
  accessToken: string
}

let publisherCredentials: PublisherCredentials | null = null
let unloadHandlersInstalled = false

export function setBroadcastPublisherCredentials(
  next: PublisherCredentials | null
): void {
  publisherCredentials = next
  if (next) {
    installBroadcastUnloadHandlers()
  }
}

export function getBroadcastPublisherCredentials(): PublisherCredentials | null {
  return publisherCredentials
}

function installBroadcastUnloadHandlers(): void {
  if (typeof window === "undefined" || unloadHandlersInstalled) return
  unloadHandlersInstalled = true

  const sendStopBeacon = () => {
    const creds = publisherCredentials
    if (!creds?.roomId || !creds.sessionId || !creds.accessToken) return

    const payload = JSON.stringify({
      roomId: creds.roomId,
      sessionId: creds.sessionId,
      reason: "page_unload",
    })

    const url = "/api/livekit/broadcast/stop"

    try {
      void fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${creds.accessToken}`,
        },
        body: payload,
        keepalive: true,
      })
    } catch {
      // ignore
    }

  }

  window.addEventListener("pagehide", (event) => {
    if (event.persisted) return
    sendStopBeacon()
  })
}
