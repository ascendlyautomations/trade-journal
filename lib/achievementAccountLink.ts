import type { TradeAccountOption } from "@/app/components/TradeAccountPicker"
import {
  ACHIEVEMENT_TYPE,
  canonicalAchievementType,
} from "./achievementTypes"
import {
  formatPropFirmMilestoneAccountLabel,
  type PropFirmMilestoneAccount,
} from "./propfirmMilestones"
import {
  inferPropFirmName,
  isEvalPropfirmAccount,
  isFundedPropfirmAccount,
} from "./propfirmPayoutCycles"

export {
  achievementTypeRequiresTradingAccount,
} from "./achievementTypes"

export function shouldRunPropFirmPayoutWorkflow(
  type: string | null | undefined,
  account: Pick<TradeAccountOption, "category" | "mode"> | null,
  options?: { payoutAlreadyRecorded?: boolean }
): boolean {
  if (options?.payoutAlreadyRecorded) return false
  return (
    canonicalAchievementType(type) === ACHIEVEMENT_TYPE.PROP_FIRM_PAYOUT &&
    account?.category === "Prop Firm" &&
    isFundedPropfirmAccount(account.mode)
  )
}

export function shouldOpenPassedEvalContinuance(
  type: string | null | undefined,
  account: Pick<TradeAccountOption, "category" | "mode"> | null
): boolean {
  return (
    canonicalAchievementType(type) === ACHIEVEMENT_TYPE.PASSED_EVAL &&
    account?.category === "Prop Firm" &&
    isEvalPropfirmAccount(account.mode)
  )
}

export function buildAchievementAccountSnapshot(account: TradeAccountOption): {
  account_id: string
  account_name: string
  account_size: string
  firm: string | null
  mode: string | null
  account_type: string | null
} {
  const accountLabel = formatPropFirmMilestoneAccountLabel({
    id: account.id,
    name: account.name,
    account_size: account.size,
    account_number: account.account_number,
    mode: account.mode,
  })
  const firm = inferPropFirmName(account.name)

  return {
    account_id: account.id,
    account_name: accountLabel,
    account_size: account.size,
    firm: firm || null,
    mode: account.mode,
    account_type: account.category ?? null,
  }
}

export function tradeAccountToPropFirmMilestoneAccount(
  account: TradeAccountOption
): PropFirmMilestoneAccount {
  return {
    id: account.id,
    name: account.name,
    account_size: account.size,
    account_number: account.account_number,
    mode: account.mode,
    consistency: account.consistency ?? null,
    max_drawdown: account.max_drawdown ?? null,
    daily_drawdown: account.daily_drawdown ?? null,
    profit_target: account.profit_target ?? null,
    winning_days: account.winning_days ?? null,
    winning_day_threshold: account.winning_day_threshold ?? null,
  }
}

export function findTradeAccountById(
  accounts: TradeAccountOption[],
  accountId: string | null | undefined
): TradeAccountOption | null {
  const id = String(accountId ?? "").trim()
  if (!id) return null
  return accounts.find((account) => String(account.id) === id) ?? null
}
