import {
  isEvalPropfirmAccount,
  isFundedPropfirmAccount,
} from "@/lib/propfirmPayoutCycles"

const PROP_FIRM_CATEGORY = "prop firm"

export type AccountPayoutPolicyInput = {
  category?: unknown
  mode?: unknown
}

function normalizeAccountMode(mode: unknown): string {
  return String(mode ?? "")
    .trim()
    .toLowerCase()
}

export function isPropFirmTradingAccount(
  account: AccountPayoutPolicyInput | null | undefined
): boolean {
  return (
    String(account?.category ?? "")
      .trim()
      .toLowerCase() === PROP_FIRM_CATEGORY
  )
}

/** Funded prop-firm accounts use `record_account_payout` + cycle history. */
export function supportsRecordPayout(
  account: AccountPayoutPolicyInput | null | undefined
): boolean {
  return (
    isPropFirmTradingAccount(account) &&
    isFundedPropfirmAccount(account?.mode)
  )
}

/** Manual ledger (`account_payout_entries`) — not for funded prop cycles. */
export function supportsManualPayoutLedger(
  account: AccountPayoutPolicyInput | null | undefined
): boolean {
  if (supportsRecordPayout(account)) return false
  const mode = normalizeAccountMode(account?.mode)
  if (
    isEvalPropfirmAccount(account?.mode) ||
    mode === "sim" ||
    mode === "backtest"
  ) {
    return false
  }
  return true
}

/** Create → Withdrawal — Live (manual ledger) or Funded prop-firm (cycle record flow). */
export function supportsWithdrawal(
  account: AccountPayoutPolicyInput | null | undefined
): boolean {
  return (
    supportsRecordPayout(account) || supportsManualPayoutLedger(account)
  )
}

export function supportsLiveWithdrawal(
  account: AccountPayoutPolicyInput | null | undefined
): boolean {
  const mode = normalizeAccountMode(account?.mode)
  return (
    (mode === "live" || mode === "") &&
    supportsManualPayoutLedger(account)
  )
}
