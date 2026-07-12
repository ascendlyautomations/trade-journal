import type { SupabaseClient } from "@supabase/supabase-js"
import { tradesInsertRowsPrivate } from "@/lib/csvTradeParsers"
import { assertAccountAllowsNewTrades } from "@/lib/freePlanAccountSlots"

/** Same shape as `InputTradeForm`’s `selectedAccount` (name/size from `accounts` table). */
export type CsvSelectedAccount = {
  id: string
  name: string
  size: string
  mode: string | null
  category?: string | null
}

export type InsertCsvTradesWithAccountOptions = {
  isInitialImport?: boolean
}

/**
 * CSV bulk insert with account fields — aligns with manual trade rows (`account_type` / `mode` from account).
 */
export async function insertCsvTradesWithAccount(
  client: SupabaseClient,
  parsedTrades: any[],
  selectedAccount: CsvSelectedAccount,
  insertOptions?: InsertCsvTradesWithAccountOptions
) {
  const {
    data: { user },
  } = await client.auth.getUser()
  if (!user) {
    return {
      data: null,
      error: { message: "Unauthorized", code: "UNAUTHORIZED" },
    }
  }

  const { data: profile } = await client
    .from("profiles")
    .select("is_pro, subscription_status, trial_end")
    .eq("id", user.id)
    .maybeSingle()

  const entryGate = await assertAccountAllowsNewTrades(
    client,
    user.id,
    selectedAccount.id,
    profile
  )
  if (!entryGate.ok) {
    return {
      data: null,
      error: {
        message: entryGate.message,
        code:
          entryGate.code === "selection_required"
            ? "ACCOUNT_SLOT_SELECTION_REQUIRED"
            : entryGate.code === "read_only"
              ? "ACCOUNT_READ_ONLY"
              : "ACCOUNT_MISSING",
      },
    }
  }

  const modeDisplay = String(selectedAccount.mode ?? "live").trim() || "live"
  const accountType = modeDisplay.toLowerCase()

  const finalTrades = parsedTrades.map((trade: any) => ({
    ...trade,
    account_name: selectedAccount.name,
    account_size: selectedAccount.size,
    account_id: selectedAccount.id,
    mode: modeDisplay,
    account_type: accountType,
    ...(selectedAccount.category != null &&
    String(selectedAccount.category).trim() !== ""
      ? { account_category: selectedAccount.category }
      : {}),
  }))

  const rows = tradesInsertRowsPrivate(finalTrades, {
    forceImportedAccountType: false,
    ...(typeof insertOptions?.isInitialImport === "boolean"
      ? { isInitialImport: insertOptions.isInitialImport }
      : {}),
  })
  return client.from("trades").insert(rows)
}
