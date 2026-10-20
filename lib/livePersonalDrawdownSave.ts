import type { SupabaseClient } from "@supabase/supabase-js"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
import {
  buildLivePersonalDrawdownAccountUpdate,
  type LivePersonalDrawdownConfig,
} from "@/lib/livePersonalDrawdown"

export type SavedLivePersonalDrawdownAccountRow = {
  id: string
  max_drawdown: number | null
  drawdown_type: string | null
}

export async function saveLivePersonalDrawdownConfig(
  supabase: SupabaseClient,
  userId: string,
  accountId: string,
  config: LivePersonalDrawdownConfig | null
): Promise<
  | { ok: true; row: SavedLivePersonalDrawdownAccountRow }
  | { ok: false; message: string }
> {
  const ownerId = String(userId).trim()
  const id = String(accountId).trim()
  if (!ownerId) {
    return { ok: false, message: "You must be signed in to save drawdown settings." }
  }
  if (!id) {
    return { ok: false, message: "Account is required." }
  }

  const patch = buildLivePersonalDrawdownAccountUpdate(config)
  const { data, error } = await supabase
    .from("accounts")
    .update(patch)
    .eq("id", id)
    .eq("user_id", ownerId)
    .select("id,max_drawdown,drawdown_type")
    .maybeSingle()

  if (error) {
    return { ok: false, message: handleSupabaseError(error) }
  }

  if (!data) {
    return {
      ok: false,
      message:
        "Account not found or drawdown settings could not be updated. Select a Live account you own.",
    }
  }

  return { ok: true, row: data as SavedLivePersonalDrawdownAccountRow }
}
