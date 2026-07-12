import type { SupabaseClient } from "@supabase/supabase-js"

/** After Pro / trial entitlement is restored, every account may receive trades again. */
export async function enableAllAccountsForTradeEntry(
  client: SupabaseClient,
  userId: string
): Promise<void> {
  const { error } = await client
    .from("accounts")
    .update({ can_add_trades: true })
    .eq("user_id", userId)

  if (error) {
    console.error("[enableAllAccountsForTradeEntry]", error)
  }
}
