import type { SupabaseClient } from "@supabase/supabase-js"
import type { AchievementUploadInitialValues } from "@/app/components/AchievementUploadModal"
import { ACHIEVEMENT_TYPE } from "@/lib/achievements"
import { getDefaultAchievementDateInputValue } from "@/lib/achievementDate"
import { resolveAccountModeForSave } from "@/lib/createAccountForm"
import { formatAccountNameWithSizeDisplay } from "@/lib/tradeAccountDisplay"
import {
  insertTradingAccount,
  updateTradingAccount,
  type CreateTradingAccountPayload,
  type TradingAccountListItem,
} from "@/lib/tradingAccounts"
import { inferPropFirmName } from "@/lib/propfirmPayoutCycles"

export type PropFirmMilestoneKind = "payout" | "passed_eval"

export type PropFirmMilestoneAccount = {
  id: string | number
  name?: string | null
  account_size?: unknown
  account_number?: string | null
  mode?: string | null
  consistency?: number | string | null
  max_drawdown?: number | string | null
  daily_drawdown?: number | string | null
  profit_target?: number | string | null
  winning_days?: number | string | null
  winning_day_threshold?: number | string | null
}

function parseOptionalNumber(value: unknown): number | null {
  if (value == null || value === "") return null
  const parsed = Number(value)
  return Number.isFinite(parsed) ? parsed : null
}

export function formatPropFirmMilestoneAccountLabel(
  account: PropFirmMilestoneAccount
): string {
  const nameSize = formatAccountNameWithSizeDisplay(
    account.name ?? "",
    account.account_size as string | null | undefined
  )
  return nameSize || String(account.name ?? "").trim() || "Prop Firm Account"
}

export function buildPropFirmMilestoneAchievementInitials(
  kind: PropFirmMilestoneKind,
  account: PropFirmMilestoneAccount,
  options?: { payoutAmount?: number }
): AchievementUploadInitialValues {
  const accountLabel = formatPropFirmMilestoneAccountLabel(account)
  const firm = inferPropFirmName(account.name)
  const achievedAt = getDefaultAchievementDateInputValue()
  const accountSize =
    account.account_size != null ? String(account.account_size) : ""

  if (kind === "payout") {
    const payoutAmount =
      options?.payoutAmount != null && Number.isFinite(options.payoutAmount)
        ? String(options.payoutAmount)
        : ""

    return {
      achievement_type: ACHIEVEMENT_TYPE.PROP_FIRM_PAYOUT,
      payout_amount: payoutAmount,
      achieved_at: achievedAt,
      title: firm ? `${firm} Payout` : `${accountLabel} Payout`,
      account_name: accountLabel,
      firm: firm || undefined,
      account_size: accountSize || undefined,
      is_public: true,
      metadata: { source: "prop_firm_mode" },
    }
  }

  return {
    achievement_type: "passed_eval",
    achieved_at: achievedAt,
    title: firm ? `${firm} Passed Eval` : `${accountLabel} Passed Eval`,
    account_name: accountLabel,
    firm: firm || undefined,
    account_size: accountSize || undefined,
    is_public: true,
    metadata: { source: "prop_firm_mode" },
  }
}

export function propFirmMilestoneUploadConfig(kind: PropFirmMilestoneKind): {
  dialogTitle: string
  dialogSubtitle: string
  saveLabel: string
  lockAchievementType: boolean
} {
  if (kind === "payout") {
    return {
      dialogTitle: "Share Your Payout",
      dialogSubtitle:
        "Upload your real payout certificate screenshot. This uses the same achievement flow as the Achievements page.",
      saveLabel: "Save Achievement",
      lockAchievementType: true,
    }
  }

  return {
    dialogTitle: "Share Your Passed Evaluation",
    dialogSubtitle:
      "Upload your real evaluation certificate. This uses the same achievement flow as the Achievements page.",
    saveLabel: "Save Achievement",
    lockAchievementType: true,
  }
}

export function buildFundedAccountPayloadFromEval(
  account: PropFirmMilestoneAccount,
  nickname?: string
): CreateTradingAccountPayload {
  const firm = inferPropFirmName(account.name)
  const sizeDigits = String(account.account_size ?? "").replace(/\D/g, "")
  const defaultName = firm ? `${firm} Funded` : "Funded Account"

  return {
    name: nickname?.trim() || defaultName,
    size: sizeDigits,
    id: String(account.account_number ?? "").trim(),
    category: "Prop Firm",
    mode: resolveAccountModeForSave("Prop Firm", "Funded"),
    rules: {
      consistency: parseOptionalNumber(account.consistency),
      maxDrawdown: parseOptionalNumber(account.max_drawdown),
      dailyDrawdown: parseOptionalNumber(account.daily_drawdown),
      profitTarget: parseOptionalNumber(account.profit_target),
      winningDays: parseOptionalNumber(account.winning_days),
      winningDayThreshold: parseOptionalNumber(account.winning_day_threshold),
    },
  }
}

export function buildConvertEvalToFundedFormInitial(
  account: PropFirmMilestoneAccount
) {
  const sizeDigits = String(account.account_size ?? "").replace(/\D/g, "")
  return {
    name: String(account.name ?? "").trim(),
    size: sizeDigits,
    accountNumber: String(account.account_number ?? "").trim(),
    category: "Prop Firm" as const,
    mode: "Funded",
    rules: {
      consistency: parseOptionalNumber(account.consistency),
      maxDrawdown: parseOptionalNumber(account.max_drawdown),
      dailyDrawdown: parseOptionalNumber(account.daily_drawdown),
      profitTarget: parseOptionalNumber(account.profit_target),
      winningDays: parseOptionalNumber(account.winning_days),
      winningDayThreshold: parseOptionalNumber(account.winning_day_threshold),
    },
  }
}

export function milestoneAccountToTradingListItem(
  account: PropFirmMilestoneAccount
): TradingAccountListItem {
  const category = "Prop Firm"
  return {
    name: String(account.name ?? ""),
    size:
      account.account_size != null ? String(account.account_size).replace(/\D/g, "") : "",
    id: String(account.id),
    account_number:
      account.account_number != null ? String(account.account_number) : null,
    mode: account.mode != null ? String(account.mode) : null,
    category,
    is_active: true,
    note: "",
    rules: {
      consistency: parseOptionalNumber(account.consistency),
      maxDrawdown: parseOptionalNumber(account.max_drawdown),
      dailyDrawdown: parseOptionalNumber(account.daily_drawdown),
      profitTarget: parseOptionalNumber(account.profit_target),
      winningDays: parseOptionalNumber(account.winning_days),
      winningDayThreshold: parseOptionalNumber(account.winning_day_threshold),
    },
  }
}

export async function convertEvalAccountToFundedWithRules(
  client: SupabaseClient,
  userId: string,
  account: PropFirmMilestoneAccount,
  payload: CreateTradingAccountPayload
): Promise<{ account: TradingAccountListItem | null; error: Error | null }> {
  return updateTradingAccount(
    client,
    userId,
    String(account.id),
    {
      ...payload,
      category: "Prop Firm",
      mode: resolveAccountModeForSave("Prop Firm", "Funded"),
    },
    milestoneAccountToTradingListItem(account)
  )
}

export function buildCreateFundedAccountFormInitial(
  account: PropFirmMilestoneAccount
) {
  const payload = buildFundedAccountPayloadFromEval(account)
  return {
    name: payload.name,
    size: payload.size,
    accountNumber: payload.id,
    category: "Prop Firm" as const,
    mode: "Funded",
    rules: payload.rules,
  }
}

export async function convertPropFirmAccountToFunded(
  client: SupabaseClient,
  userId: string,
  accountId: string | number,
  account?: PropFirmMilestoneAccount
): Promise<{ error: Error | null }> {
  if (account) {
    const payload = buildConvertEvalToFundedFormInitial(account)
    const { error } = await convertEvalAccountToFundedWithRules(
      client,
      userId,
      account,
      {
        name: payload.name,
        size: payload.size,
        id: payload.accountNumber,
        category: "Prop Firm",
        mode: resolveAccountModeForSave("Prop Firm", "Funded"),
        rules: payload.rules,
      }
    )
    return { error }
  }

  const { error } = await client
    .from("accounts")
    .update({ mode: "Funded" })
    .eq("id", accountId)
    .eq("user_id", userId)

  if (error) {
    return { error: new Error(error.message) }
  }

  return { error: null }
}

export async function createFundedAccountFromEval(
  client: SupabaseClient,
  userId: string,
  account: PropFirmMilestoneAccount,
  nickname?: string
): Promise<{ account: TradingAccountListItem | null; error: Error | null }> {
  return insertTradingAccount(
    client,
    userId,
    buildFundedAccountPayloadFromEval(account, nickname)
  )
}
