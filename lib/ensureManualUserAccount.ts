import type { SupabaseClient } from "@supabase/supabase-js"
import { FREE_PLAN_ACCOUNT_LIMIT } from "@/lib/tradingAccounts"

function isImportedType(t: string | null | undefined) {
  return String(t ?? "")
    .toLowerCase()
    .trim() === "imported"
}

/**
 * Ensures this account_name is registered for the user before a non-imported trade is saved.
 * Free users may register up to FREE_PLAN_ACCOUNT_LIMIT manual (non-imported) account names.
 */
export async function ensureManualUserAccountRegistered(
  supabase: SupabaseClient,
  params: {
    userId: string
    /** Firm / display name; empty string is allowed as one logical account */
    accountName: string | null | undefined
    /** Same as trade account_type / mode (e.g. live, eval, funded) */
    tradeAccountType: string
    isPro: boolean
    /** Skip when trade is backtest-only or CSV-import style */
    skipRegistry: boolean
  }
): Promise<{ ok: true } | { ok: false; reason: "limit" | "error" }> {
  const { userId, accountName, tradeAccountType, isPro, skipRegistry } = params

  if (skipRegistry || isImportedType(tradeAccountType)) {
    return { ok: true }
  }

  const account_name = String(accountName ?? "").trim()

  const { data: existing } = await supabase
    .from("user_accounts")
    .select("id")
    .eq("user_id", userId)
    .eq("account_name", account_name)
    .maybeSingle()

  if (existing) return { ok: true }

  const { data: accounts } = await supabase
    .from("user_accounts")
    .select("account_type")
    .eq("user_id", userId)

  const manualAccounts = (accounts ?? []).filter((a) => !isImportedType(a.account_type))

  if (!isPro && manualAccounts.length >= FREE_PLAN_ACCOUNT_LIMIT) {
    return { ok: false, reason: "limit" }
  }

  const account_type = tradeAccountType || "manual"

  const { error } = await supabase.from("user_accounts").insert({
    user_id: userId,
    account_name,
    account_type,
  })

  if (error) {
    if (error.code === "23505") return { ok: true }
    console.error("user_accounts insert:", error)
    return { ok: false, reason: "error" }
  }

  return { ok: true }
}

/** Single row so CSV imports are labeled; does not consume the free manual slot (type imported). */
export async function ensureImportedCsvAccountRegistered(
  supabase: SupabaseClient,
  userId: string
): Promise<{ error: Error | null }> {
  const { error } = await supabase.from("user_accounts").upsert(
    {
      user_id: userId,
      account_name: "Imported",
      account_type: "imported",
    },
    { onConflict: "user_id,account_name" }
  )

  return { error: error ? new Error(error.message) : null }
}
