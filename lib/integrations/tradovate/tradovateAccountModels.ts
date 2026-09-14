/** Normalized safe view of a Tradovate Account entity (GET /v1/account/list). */
export type TradovateDiscoveredAccount = {
  externalAccountId: string
  name: string
  displayName: string | null
  accountType: string | null
  marginAccountType: string | null
  legalStatus: string | null
  active: boolean | null
  closed: boolean | null
  restricted: boolean | null
  readonly: boolean | null
  evaluationSize: number | null
  providerUserId: string | null
}

export type TradovateAccountListItemRaw = {
  id?: number
  name?: string
  userId?: number
  accountType?: string
  marginAccountType?: string
  legalStatus?: string
  closed?: boolean
  restricted?: boolean
  readonly?: boolean
  evaluationSize?: number
  ccEmail?: string
}

export function normalizeTradovateAccountRow(
  raw: TradovateAccountListItemRaw
): TradovateDiscoveredAccount | null {
  if (raw.id == null || Number.isNaN(Number(raw.id))) return null
  const externalAccountId = String(raw.id)
  const name = typeof raw.name === "string" && raw.name.trim() ? raw.name.trim() : externalAccountId

  const closed = typeof raw.closed === "boolean" ? raw.closed : null
  const active = closed === null ? null : !closed

  return {
    externalAccountId,
    name,
    displayName: name,
    accountType: typeof raw.accountType === "string" ? raw.accountType : null,
    marginAccountType:
      typeof raw.marginAccountType === "string" ? raw.marginAccountType : null,
    legalStatus: typeof raw.legalStatus === "string" ? raw.legalStatus : null,
    active,
    closed,
    restricted: typeof raw.restricted === "boolean" ? raw.restricted : null,
    readonly: typeof raw.readonly === "boolean" ? raw.readonly : null,
    evaluationSize:
      typeof raw.evaluationSize === "number" && Number.isFinite(raw.evaluationSize)
        ? raw.evaluationSize
        : null,
    providerUserId: raw.userId != null ? String(raw.userId) : null,
  }
}

export function tradovateAccountSafeMetadata(
  account: TradovateDiscoveredAccount
): Record<string, unknown> {
  return {
    accountType: account.accountType,
    marginAccountType: account.marginAccountType,
    legalStatus: account.legalStatus,
    active: account.active,
    closed: account.closed,
    restricted: account.restricted,
    readonly: account.readonly,
    evaluationSize: account.evaluationSize,
    providerUserId: account.providerUserId,
  }
}
