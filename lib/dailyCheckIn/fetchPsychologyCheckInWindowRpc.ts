import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import { isCopyGroupFilterValue } from "@/lib/tradeAccountSelection"
import { waitForDailyCheckInAuthSession } from "@/lib/dailyCheckIn/authSession.ts"
import { mapCheckInRow } from "@/lib/dailyCheckIn/repository.ts"
import type { TraderDailyCheckIn } from "@/lib/dailyCheckIn/types.ts"

type PsychologyCheckInWindowPayload = {
  data?: {
    check_ins?: unknown[]
  }
}

function parsePsychologyCheckInWindowRows(
  data: unknown
): TraderDailyCheckIn[] {
  if (!data || typeof data !== "object") return []
  const payload = data as PsychologyCheckInWindowPayload
  const rows = payload.data?.check_ins
  if (!Array.isArray(rows)) return []
  return rows
    .map((row) => mapCheckInRow(row as Record<string, unknown>))
    .filter((row): row is TraderDailyCheckIn => row != null)
}

/** Same RPC as iOS `PsychologyCheckInBootstrapLoader` / dashboard psychology hydrate. */
export async function fetchPsychologyCheckInWindowRpc(
  supabase: SupabaseClient<Database>,
  accountFilter?: string | null
): Promise<TraderDailyCheckIn[]> {
  const authReady = await waitForDailyCheckInAuthSession(supabase)
  if (!authReady) {
    throw new Error("Sign in to load daily check-ins.")
  }

  const args: { p_account_id?: string } = {}
  if (
    accountFilter &&
    accountFilter !== "all" &&
    !isCopyGroupFilterValue(accountFilter)
  ) {
    args.p_account_id = accountFilter
  }

  const { data, error } = await supabase.rpc(
    "rpc_v1_psychology_check_in_window",
    args
  )
  if (error) throw error
  return parsePsychologyCheckInWindowRows(data)
}
