import type { SupabaseClient } from "@supabase/supabase-js"

export async function markProfileUseFreeTier(
  supabase: SupabaseClient,
  userId: string
): Promise<{ ok: boolean; error?: string }> {
  const { error } = await supabase
    .from("profiles")
    .update({ use_free_tier: true })
    .eq("id", userId)

  if (error) {
    return { ok: false, error: error.message }
  }

  return { ok: true }
}
