import type { RithmicDiscoveredAccountRow } from "@/lib/integrations/rithmic/rithmicProtocolClient"
import { maskBrokerIdentifier } from "@/lib/integrations/rithmic/rithmicSyncLogger"

/** Stable external identity: FCM + IB + account id (per official account list fields). */
export function rithmicExternalAccountId(row: {
  fcmId: string
  ibId: string
  accountId: string
}): string {
  return `${row.fcmId}|${row.ibId}|${row.accountId}`
}

export type RithmicDiscoveredAccount = {
  externalAccountId: string
  name: string | null
  displayName: string | null
  fcmId: string
  ibId: string
  accountId: string
  accountCurrency: string | null
  metadata: Record<string, unknown>
}

export function normalizeRithmicDiscoveredAccount(
  row: RithmicDiscoveredAccountRow
): RithmicDiscoveredAccount {
  const externalAccountId = rithmicExternalAccountId(row)
  const name = row.accountName?.trim() || null
  return {
    externalAccountId,
    name,
    displayName: name,
    fcmId: row.fcmId,
    ibId: row.ibId,
    accountId: row.accountId,
    accountCurrency: row.accountCurrency,
    metadata: rithmicAccountSafeMetadata(row),
  }
}

export function rithmicAccountSafeMetadata(
  row: RithmicDiscoveredAccountRow
): Record<string, unknown> {
  return {
    provider: "rithmic",
    fcm_id: row.fcmId,
    ib_id: row.ibId,
    account_id: row.accountId,
    account_currency: row.accountCurrency,
    loss_limit: row.lossLimit,
    account_auto_liquidate: row.accountAutoLiquidate,
    auto_liq_threshold_current_value: row.autoLiqThresholdCurrentValue,
  }
}

export type SafeRithmicDiscoveredAccountView = {
  externalAccountId: string
  accountName: string | null
  accountCurrency: string | null
  fcmIdMasked: string
  ibIdMasked: string
  accountIdMasked: string
}

export function toSafeRithmicDiscoveredAccountView(
  account: RithmicDiscoveredAccount
): SafeRithmicDiscoveredAccountView {
  return {
    externalAccountId: maskBrokerIdentifier(account.externalAccountId),
    accountName: account.name,
    accountCurrency: account.accountCurrency,
    fcmIdMasked: maskBrokerIdentifier(account.fcmId),
    ibIdMasked: maskBrokerIdentifier(account.ibId),
    accountIdMasked: maskBrokerIdentifier(account.accountId),
  }
}
