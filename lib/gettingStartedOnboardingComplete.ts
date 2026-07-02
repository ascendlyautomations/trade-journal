import type { SupabaseClient } from "@supabase/supabase-js"
import { gsDebug } from "@/lib/gettingStartedDebug"
import { isDemoSupabaseBlocked } from "@/lib/demo/demoSupabaseGuard"

export const ONBOARDING_COMPLETE_POPUP_TITLE =
  "🎉 You Have Completed All Onboarding Tasks"

export async function markOnboardingCompletePopupSeen(
  supabase: SupabaseClient,
  userId: string
): Promise<boolean> {
  if (isDemoSupabaseBlocked()) return true

  gsDebug("markOnboardingCompletePopupSeen: before", {
    userId: userId.slice(0, 8),
  })

  const { data: rpcOk, error: rpcError } = await supabase.rpc(
    "mark_onboarding_complete_popup_seen"
  )

  if (!rpcError && rpcOk === true) {
    gsDebug("markOnboardingCompletePopupSeen: after (rpc)", { ok: true })
    return true
  }

  if (rpcError) {
    gsDebug(
      "markOnboardingCompletePopupSeen: rpc failed, falling back to update",
      {
        message: rpcError.message,
        code: rpcError.code,
      }
    )
  }

  const { data, error } = await supabase
    .from("profiles")
    .update({ has_seen_onboarding_complete_popup: true })
    .eq("id", userId)
    .select("has_seen_onboarding_complete_popup")
    .single()

  const ok = !error && data?.has_seen_onboarding_complete_popup === true

  gsDebug("markOnboardingCompletePopupSeen: after (update)", {
    ok,
    returned: data?.has_seen_onboarding_complete_popup ?? null,
    error: error?.message ?? null,
    code: error?.code ?? null,
  })

  if (!ok) {
    console.error("markOnboardingCompletePopupSeen failed:", rpcError ?? error)
  }

  return ok
}
