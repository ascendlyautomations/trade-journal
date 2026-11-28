import type { SupabaseClient } from "@supabase/supabase-js"
import { resolveAccountModeForSave } from "@/lib/createAccountForm"
import { isEvalPropfirmAccount } from "@/lib/propfirmPayoutCycles"
import type { PropFirmMilestoneAccount } from "@/lib/propfirmMilestones"
import { syncPropFirmAccountPurchaseExpense } from "@/lib/propFirmExpenses"
import {
  mapTradingAccountRow,
  type CreateTradingAccountPayload,
  type TradingAccountListItem,
} from "@/lib/tradingAccounts"

export type AccountLifecycleFields = {
  account_lifecycle_id?: string | null
  graduated_to_account_id?: string | null
  graduated_from_account_id?: string | null
}

export function accountLifecycleId(
  account: AccountLifecycleFields & { id?: string | null }
): string {
  const lifecycle = String(account.account_lifecycle_id ?? "").trim()
  const id = String(account.id ?? "").trim()
  return lifecycle || id
}

export function countDistinctAccountSlots(
  accounts: readonly (AccountLifecycleFields & { id?: string | null })[]
): number {
  const slots = new Set<string>()
  for (const row of accounts) {
    const slot = accountLifecycleId(row)
    if (slot) slots.add(slot)
  }
  return slots.size
}

export function isCompletedEvaluationAccount(
  account: Pick<TradingAccountListItem, "graduated_to_account_id" | "mode" | "category">
): boolean {
  return Boolean(String(account.graduated_to_account_id ?? "").trim())
}

export function isFundedLifecycleSuccessor(
  account: Pick<TradingAccountListItem, "graduated_from_account_id">
): boolean {
  return Boolean(String(account.graduated_from_account_id ?? "").trim())
}

export function milestoneAccountFromListItem(
  account: TradingAccountListItem
): PropFirmMilestoneAccount {
  return {
    id: account.id,
    name: account.name,
    account_size: account.size,
    account_number: account.account_number,
    mode: account.mode,
    consistency: account.rules?.consistency ?? null,
    max_drawdown: account.rules?.maxDrawdown ?? null,
    daily_drawdown: account.rules?.dailyDrawdown ?? null,
    profit_target: account.rules?.profitTarget ?? null,
    winning_days: account.rules?.winningDays ?? null,
    winning_day_threshold: account.rules?.winningDayThreshold ?? null,
  }
}

export function canUpgradeEvaluationToFunded(
  account: Pick<
    TradingAccountListItem,
    "category" | "mode" | "graduated_to_account_id"
  >
): boolean {
  const category = String(account.category ?? "").trim().toLowerCase()
  if (category !== "prop firm" && category !== "propfirm") return false
  if (!isEvalPropfirmAccount(account.mode)) return false
  if (isCompletedEvaluationAccount(account)) return false
  return true
}

export type TradingAccountManagementRow =
  | { kind: "standalone"; account: TradingAccountListItem }
  | {
      kind: "lifecycle"
      funded: TradingAccountListItem
      evaluation: TradingAccountListItem | null
    }

/** Settings list: funded successor with completed eval nested beneath (no dropdown changes). */
export function buildTradingAccountManagementRows(
  accounts: TradingAccountListItem[]
): TradingAccountManagementRow[] {
  const byId = new Map(accounts.map((a) => [a.id, a]))
  const consumedEval = new Set<string>()
  const rows: TradingAccountManagementRow[] = []

  for (const account of accounts) {
    const fromEvalId = String(account.graduated_from_account_id ?? "").trim()
    if (fromEvalId) {
      const evalRow = byId.get(fromEvalId) ?? null
      rows.push({ kind: "lifecycle", funded: account, evaluation: evalRow })
      if (evalRow) consumedEval.add(evalRow.id)
      continue
    }
    if (isCompletedEvaluationAccount(account)) {
      consumedEval.add(account.id)
      continue
    }
    rows.push({ kind: "standalone", account })
  }

  for (const account of accounts) {
    if (consumedEval.has(account.id)) continue
    if (
      rows.some(
        (row) =>
          row.kind === "standalone" && row.account.id === account.id
      )
    ) {
      continue
    }
    if (
      rows.some(
        (row) =>
          row.kind === "lifecycle" &&
          (row.funded.id === account.id ||
            row.evaluation?.id === account.id)
      )
    ) {
      continue
    }
    rows.push({ kind: "standalone", account })
  }

  return rows.sort((a, b) => {
    const title = (row: TradingAccountManagementRow) =>
      row.kind === "lifecycle" ? row.funded.name : row.account.name
    return title(a).localeCompare(title(b), undefined, { sensitivity: "base" })
  })
}

function graduationPayloadFromCreate(
  payload: CreateTradingAccountPayload
): Record<string, unknown> {
  return {
    name: payload.name.trim(),
    account_size: payload.size.trim() || null,
    account_number: payload.id.trim() || null,
    category: payload.category,
    mode: resolveAccountModeForSave(payload.category, payload.mode ?? "Funded"),
    consistency: payload.rules?.consistency ?? null,
    max_drawdown: payload.rules?.maxDrawdown ?? null,
    daily_drawdown: payload.rules?.dailyDrawdown ?? null,
    profit_target: payload.rules?.profitTarget ?? null,
    winning_days: payload.rules?.winningDays ?? null,
    winning_day_threshold: payload.rules?.winningDayThreshold ?? null,
  }
}

/** Server graduation: funded successor without consuming another free-plan slot. */
export async function graduateEvalToFunded(
  client: SupabaseClient,
  userId: string,
  evalAccountId: string,
  payload: CreateTradingAccountPayload
): Promise<{
  fundedAccount: TradingAccountListItem | null
  error: Error | null
  purchaseExpenseWarning?: string | null
}> {
  const name = payload.name.trim()
  if (!name) {
    return { fundedAccount: null, error: new Error("Account name is required") }
  }

  const { data, error } = await client.rpc("graduate_eval_to_funded", {
    p_eval_account_id: evalAccountId,
    p_payload: graduationPayloadFromCreate({
      ...payload,
      category: "Prop Firm",
      mode: resolveAccountModeForSave("Prop Firm", "Funded"),
    }),
  })

  if (error) {
    return { fundedAccount: null, error: new Error(error.message) }
  }

  if (!data) {
    return {
      fundedAccount: null,
      error: new Error("Funded account was not created"),
    }
  }

  const funded = mapTradingAccountRow(data as Record<string, unknown>)
  const purchaseExpenseWarning =
    (await syncPropFirmAccountPurchaseExpense(client, userId, funded.id, {
      name: funded.name,
      category: String(funded.category ?? payload.category),
      mode: funded.mode ?? payload.mode,
      purchaseCost: payload.purchaseCost,
      purchaseDate: payload.purchaseDate,
    })) ?? null

  return {
    fundedAccount: funded,
    error: null,
    purchaseExpenseWarning:
      purchaseExpenseWarning && purchaseExpenseWarning.length > 0
        ? purchaseExpenseWarning
        : null,
  }
}