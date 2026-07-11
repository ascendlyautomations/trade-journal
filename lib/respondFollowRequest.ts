import type { SupabaseClient } from "@supabase/supabase-js"
import {
  toUserFacingErrorMessage,
  USER_FACING_ERROR_MESSAGES,
} from "@/lib/userFacingError"

async function authPost(
  supabase: SupabaseClient,
  url: string,
  body: { requestId: string }
): Promise<{ ok: true } | { ok: false; message: string }> {
  const {
    data: { session },
  } = await supabase.auth.getSession()
  const accessToken = session?.access_token
  if (!accessToken) {
    return { ok: false, message: USER_FACING_ERROR_MESSAGES.SESSION_EXPIRED }
  }

  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify(body),
  })

  if (!res.ok) {
    const text = await res.text()
    console.error("[follow-requests] API failed", { url, status: res.status, text })
    let payload: { error?: string; message?: string } | null = null
    try {
      payload = JSON.parse(text) as { error?: string; message?: string }
    } catch {
      // ignore non-JSON bodies
    }
    return {
      ok: false,
      message: toUserFacingErrorMessage(
        payload?.error || payload?.message || text || res.statusText
      ),
    }
  }

  window.dispatchEvent(new CustomEvent("tj-unread-notifications-refresh"))
  return { ok: true }
}

export async function approveIncomingFollowRequest(
  supabase: SupabaseClient,
  requestId: string
): Promise<{ ok: true } | { ok: false; message: string }> {
  if (!requestId) return { ok: false, message: "Invalid request" }
  return authPost(supabase, "/api/follow-requests/approve", { requestId })
}

export async function declineIncomingFollowRequest(
  supabase: SupabaseClient,
  requestId: string
): Promise<{ ok: true } | { ok: false; message: string }> {
  if (!requestId) return { ok: false, message: "Invalid request" }
  return authPost(supabase, "/api/follow-requests/decline", { requestId })
}
