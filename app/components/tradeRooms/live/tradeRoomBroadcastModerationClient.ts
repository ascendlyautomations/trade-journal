"use client"

export type BroadcastModerationClientAction =
  | "invite_speak"
  | "request_unmute"
  | "mute_speaker"
  | "revoke_speaker"
  | "remove_viewer"
  | "dismiss_hand"

export async function postBroadcastModeration(
  accessToken: string,
  body: {
    roomId: string
    sessionId: string
    targetUserId: string
    action: BroadcastModerationClientAction
    blockRejoin?: boolean
  }
): Promise<
  | { ok: true; targetDisplayName?: string | null; invitationId?: string | null }
  | { ok: false; error: string }
> {
  const res = await fetch("/api/livekit/broadcast/moderate", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify(body),
  })
  const payload = (await res.json().catch(() => ({}))) as {
    error?: string
    targetDisplayName?: string | null
    invitationId?: string | null
  }
  if (!res.ok) {
    return { ok: false, error: payload.error || "Moderation request failed." }
  }
  return {
    ok: true,
    targetDisplayName: payload.targetDisplayName ?? null,
    invitationId: payload.invitationId ?? null,
  }
}
