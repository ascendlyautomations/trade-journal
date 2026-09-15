import {
  defaultModeForAccountType,
  type AccountType,
} from "@/lib/createAccountForm"
import type { SafeBrokerIntegrationAccountView } from "@/lib/integrations/brokerIntegrationAccounts"
import type { TradingAccountPropFirmRules } from "@/lib/tradingAccounts"

export type RithmicCreateAccountInitialValues = {
  name: string
  size: string
  accountNumber: string
  category: AccountType
  mode: string
  rules: TradingAccountPropFirmRules | null
}

export function buildRithmicCreateAccountInitialValues(
  account: SafeBrokerIntegrationAccountView
): RithmicCreateAccountInitialValues {
  const meta = account.metadata ?? {}
  const accountIdFromMeta =
    typeof meta.accountId === "string" ? meta.accountId.trim() : ""

  const displayName =
    account.externalAccountName?.trim() ||
    account.externalDisplayName?.trim() ||
    accountIdFromMeta ||
    account.externalAccountId.split("|").pop()?.trim() ||
    "Rithmic account"

  const accountNumber =
    accountIdFromMeta ||
    account.externalAccountId.split("|").pop()?.trim() ||
    account.externalAccountId

  const category: AccountType = "Personal"

  return {
    name: displayName,
    accountNumber,
    size: "",
    category,
    mode: defaultModeForAccountType(category),
    rules: null,
  }
}
