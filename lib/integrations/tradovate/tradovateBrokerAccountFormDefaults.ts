import {
  defaultModeForAccountType,
  type AccountType,
} from "@/lib/createAccountForm"
import type { TradingAccountPropFirmRules } from "@/lib/tradingAccounts"

export type TradovateCreateAccountInitialValues = {
  name: string
  size: string
  accountNumber: string
  category: AccountType
  mode: string
  rules: TradingAccountPropFirmRules | null
}

export type TradovateBrokerSafeMetadata = {
  evaluationSize?: unknown
  accountType?: unknown
  marginAccountType?: unknown
  legalStatus?: unknown
  active?: unknown
  closed?: unknown
  restricted?: unknown
  readonly?: unknown
  providerUserId?: unknown
}

export function evaluationSizeFromTradovateMetadata(
  metadata: TradovateBrokerSafeMetadata | Record<string, unknown> | null | undefined
): number | null {
  const raw = metadata?.evaluationSize
  return typeof raw === "number" && Number.isFinite(raw) ? raw : null
}

/**
 * Prefill values for CreateAccountModal when linking a discovered Tradovate account.
 * Does not infer prop firm, category, or eval/funded from account name prefixes.
 */
export function buildTradovateCreateAccountInitialValues(params: {
  externalAccountId: string
  externalAccountName: string | null
  metadata?: TradovateBrokerSafeMetadata | Record<string, unknown> | null
}): TradovateCreateAccountInitialValues {
  const providerName =
    params.externalAccountName?.trim() || params.externalAccountId.trim()
  const evaluationSize = evaluationSizeFromTradovateMetadata(params.metadata)
  const size =
    evaluationSize != null ? String(Math.round(evaluationSize)) : ""

  const accountNumber = params.externalAccountName?.trim()
    ? params.externalAccountName.trim()
    : params.externalAccountId.trim()

  const category: AccountType = "Personal"

  return {
    name: providerName,
    size,
    accountNumber,
    category,
    mode: defaultModeForAccountType(category),
    rules: null,
  }
}
