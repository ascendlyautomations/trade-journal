import type { SupabaseClient } from "@supabase/supabase-js"
import {
  toUserFacingErrorMessage,
  USER_FACING_ERROR_MESSAGES,
} from "@/lib/userFacingError"

export async function markProfileUseFreeTier(
  supabase: SupabaseClient,
  userId: string
): Promise<{ ok: boolean; error?: string }> {
  const {
    data: { session },
  } = await supabase.auth.getSession()
  const accessToken = session?.access_token
  if (!accessToken) {
    return { ok: false, error: USER_FACING_ERROR_MESSAGES.SESSION_EXPIRED }
  }

  const res = await fetch("/api/profile/mark-free-tier", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
    },
  })

  if (!res.ok) {
    const payload = (await res.json().catch(() => null)) as { error?: string } | null
    console.error("[markProfileUseFreeTier] failed", {
      userId,
      status: res.status,
      error: payload?.error ?? res.statusText,
    })
    return {
      ok: false,
      error: toUserFacingErrorMessage(
        payload?.error ?? res.statusText,
        "Could not continue on Free. Please try again."
      ),
    }
  }

  return { ok: true }
}
