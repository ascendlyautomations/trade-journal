import type { SupabaseClient } from "@supabase/supabase-js"

/** Notify conversation participants via Messaging push (no Activity row). */
export async function createDirectMessagePush(
  _supabase: SupabaseClient,
  messageId: string
): Promise<boolean> {
  if (!messageId) return false

  const {
    data: { session },
  } = await _supabase.auth.getSession()
  const accessToken = session?.access_token
  if (!accessToken) {
    console.error("[messaging-dm] push skipped: no auth session")
    return false
  }

  const res = await fetch("/api/messaging/notify-dm", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({ messageId }),
  })

  if (!res.ok) {
    const body = await res.text()
    console.error("[messaging-dm] notify API failed", {
      messageId,
      status: res.status,
      body,
    })
    return false
  }

  window.dispatchEvent(new CustomEvent("tj-unread-messages-refresh"))
  return true
}
