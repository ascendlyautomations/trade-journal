import {
  assertContractVersion,
  type BootstrapMetaV1,
} from "./versioning.ts"

export type PropFirmBootstrapV1 = {
  meta: BootstrapMetaV1
  data: {
    accounts: Record<string, unknown>[]
    payout_cycles: Record<string, unknown>[]
    achievements: Record<string, unknown>[]
    trades: Record<string, unknown>[]
  }
}

export class PropFirmBootstrapContractError extends Error {
  constructor(message: string) {
    super(message)
    this.name = "PropFirmBootstrapContractError"
  }
}

function asArray(value: unknown, field: string): Record<string, unknown>[] {
  if (value == null) return []
  if (!Array.isArray(value)) {
    throw new PropFirmBootstrapContractError(`${field} must be an array`)
  }
  return value as Record<string, unknown>[]
}

export function decodePropFirmBootstrapV1(raw: unknown): PropFirmBootstrapV1 {
  if (!raw || typeof raw !== "object") {
    throw new PropFirmBootstrapContractError("bootstrap must be an object")
  }
  const payload = raw as Record<string, unknown>
  const meta = payload.meta as BootstrapMetaV1 | undefined
  assertContractVersion(meta)
  const data = payload.data as Record<string, unknown> | undefined
  if (!data || typeof data !== "object") {
    throw new PropFirmBootstrapContractError("data must be an object")
  }

  return {
    meta: meta!,
    data: {
      accounts: asArray(data.accounts, "accounts"),
      payout_cycles: asArray(data.payout_cycles, "payout_cycles"),
      achievements: asArray(data.achievements, "achievements"),
      trades: asArray(data.trades, "trades"),
    },
  }
}
