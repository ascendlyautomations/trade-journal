import type { SupabaseClient } from "@supabase/supabase-js"
import { tradesInsertRowsPrivate } from "@/lib/csvTradeParsers"

/** Same shape as `InputTradeForm`’s `selectedAccount` (name/size from `accounts` table). */
export type CsvSelectedAccount = {
  id: string
  name: string
  size: string
  mode: string | null
  category?: string | null
}

/**
 * CSV bulk insert with account fields — aligns with manual trade rows (`account_type` / `mode` from account).
 */
export async function insertCsvTradesWithAccount(
  client: SupabaseClient,
  parsedTrades: any[],
  selectedAccount: CsvSelectedAccount
) {
  const modeDisplay = String(selectedAccount.mode ?? "live").trim() || "live"
  const accountType = modeDisplay.toLowerCase()

  const finalTrades = parsedTrades.map((trade: any) => ({
    ...trade,
    account_name: selectedAccount.name,
    account_size: selectedAccount.size,
    account_id: selectedAccount.id,
    mode: modeDisplay,
    account_type: accountType,
    ...(selectedAccount.category != null && String(selectedAccount.category).trim() !== ""
      ? { account_category: selectedAccount.category }
      : {}),
  }))

  const rows = tradesInsertRowsPrivate(finalTrades, {
    forceImportedAccountType: false,
  })
  return client.from("trades").insert(rows)
}
