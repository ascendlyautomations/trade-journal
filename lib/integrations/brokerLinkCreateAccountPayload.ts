import {
  ACCOUNT_TYPES,
  assertRequiredAccountValue,
  normalizeAccountCategoryForForm,
  resolveAccountModeForSave,
} from "@/lib/createAccountForm"
import type { CreateTradingAccountPayload, TradingAccountPropFirmRules } from "@/lib/tradingAccounts"

export type BrokerLinkCreateAccountBody = {
  name?: string
  size?: string
  accountNumber?: string
  category?: string
  mode?: string | null
  rules?: TradingAccountPropFirmRules | null
}

export function parseBrokerLinkCreateAccountPayload(
  body: BrokerLinkCreateAccountBody,
  fallbackName: string
):
  | { ok: true; payload: CreateTradingAccountPayload }
  | { ok: false; message: string } {
  const name = body.name?.trim() || fallbackName
  if (!name) {
    return { ok: false, message: "Account name is required." }
  }

  const sizeGate = assertRequiredAccountValue(body.size)
  if (!sizeGate.ok) {
    return { ok: false, message: sizeGate.message }
  }

  const category = normalizeAccountCategoryForForm(body.category)
  if (!(ACCOUNT_TYPES as readonly string[]).includes(category)) {
    return { ok: false, message: "Invalid account category." }
  }

  const modeUi = body.mode?.trim() || ""
  const mode = resolveAccountModeForSave(category, modeUi || "Live")

  const rules =
    category === "Prop Firm" && body.rules && typeof body.rules === "object"
      ? (body.rules as TradingAccountPropFirmRules)
      : null

  const accountNumber = body.accountNumber?.trim() ?? ""

  return {
    ok: true,
    payload: {
      name,
      size: sizeGate.value,
      id: accountNumber,
      category,
      mode,
      rules,
    },
  }
}
