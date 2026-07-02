import type { SupabaseClient } from "@supabase/supabase-js"
import { gsDebug } from "@/lib/gettingStartedDebug"
import { isDemoSupabaseBlocked } from "@/lib/demo/demoSupabaseGuard"

export const GETTING_STARTED_INTRO_POPUP_TITLE = "Welcome to Getting Started"

export async function markGettingStartedIntroSeen(
  supabase: SupabaseClient,
  userId: string
): Promise<boolean> {
  if (isDemoSupabaseBlocked()) return true

  gsDebug("markGettingStartedIntroSeen: before", {
    userId: userId.slice(0, 8),
  })

  const { data: rpcOk, error: rpcError } = await supabase.rpc(
    "mark_getting_started_intro_seen"
  )

  if (!rpcError && rpcOk === true) {
    gsDebug("markGettingStartedIntroSeen: after (rpc)", { ok: true })
    return true
  }

  if (rpcError) {
    gsDebug("markGettingStartedIntroSeen: rpc failed, falling back to update", {
      message: rpcError.message,
      code: rpcError.code,
    })
  }

  const { data, error } = await supabase
    .from("profiles")
    .update({ has_seen_getting_started_intro: true })
    .eq("id", userId)
    .select("has_seen_getting_started_intro")
    .single()

  const ok = !error && data?.has_seen_getting_started_intro === true

  gsDebug("markGettingStartedIntroSeen: after (update)", {
    ok,
    returned: data?.has_seen_getting_started_intro ?? null,
    error: error?.message ?? null,
    code: error?.code ?? null,
  })

  if (!ok) {
    console.error("markGettingStartedIntroSeen failed:", rpcError ?? error)
  }

  return ok
}
