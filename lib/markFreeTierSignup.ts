import type { SupabaseClient } from "@supabase/supabase-js"

export async function markProfileUseFreeTier(
  supabase: SupabaseClient,
  userId: string
): Promise<{ ok: boolean; error?: string }> {
  const {
    data: { session },
  } = await supabase.auth.getSession()
  const accessToken = session?.access_token
  if (!accessToken) {
    return { ok: false, error: "Not authenticated" }
  }

  const res = await fetch("/api/profile/mark-free-tier", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
    },
  })

  if (!res.ok) {
    const payload = (await res.json().catch(() => null)) as { error?: string } | null
    return { ok: false, error: payload?.error ?? res.statusText }
  }

  return { ok: true }
}
