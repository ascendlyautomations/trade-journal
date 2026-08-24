import { isExitBeforeEntry } from "./inputTradeDateTime.ts"
import { tradeFormHasFutureDate } from "./tradeDateValidation.ts"
import { parseOptionalRr } from "./tradeRr.ts"

export type QuickTradeFormField =
  | "account"
  | "symbol"
  | "pnl"
  | "points"
  | "contracts"
  | "rr"
  | "entryDate"
  | "exitDate"
  | "entryTime"
  | "exitTime"
  | "entryPrice"
  | "exitPrice"
  | "image"
  | "direction"

export type QuickTradeValidationKind = "missing" | "invalid"

export type QuickTradeValidationFailure = {
  ok: false
  kind: QuickTradeValidationKind
  field: QuickTradeFormField
  message: string
  title?: string
}

export type QuickTradeValidationResult =
  | { ok: true }
  | QuickTradeValidationFailure

export type QuickTradeFormValidationInput = {
  hasAccount: boolean
  ticker: string
  pnl: string
  points: string
  contracts: string
  rr: string
  entryDate: string
  exitDate: string
  entryTime: string
  exitTime: string
  decimalError?: string | null
}

/** Returns the first validation issue in top-to-bottom form order. */
export function validateQuickTradeForm(
  input: QuickTradeFormValidationInput
): QuickTradeValidationResult {
  if (!input.hasAccount) {
    return {
      ok: false,
      kind: "missing",
      field: "account",
      message: "Please select a Trading Account.",
    }
  }

  if (!input.ticker.trim()) {
    return {
      ok: false,
      kind: "missing",
      field: "symbol",
      message: "Please enter a Symbol.",
    }
  }

  if (input.decimalError?.trim()) {
    return {
      ok: false,
      kind: "invalid",
      field: "pnl",
      title: "Invalid P&L",
      message: input.decimalError.trim(),
    }
  }

  const pnlRaw = String(input.pnl).replace(/,/g, "").replace(/\$/g, "")
  if (pnlRaw.trim() === "") {
    return {
      ok: false,
      kind: "missing",
      field: "pnl",
      message: "Please enter P&L.",
    }
  }
  const pnl = Number(pnlRaw)
  if (!Number.isFinite(pnl)) {
    return {
      ok: false,
      kind: "invalid",
      field: "pnl",
      title: "Invalid P&L",
      message: "Please enter a valid P&L value.",
    }
  }

  if (input.points.trim() === "") {
    return {
      ok: false,
      kind: "missing",
      field: "points",
      message: "Please enter Points.",
    }
  }
  const points = Number(String(input.points).replace(/,/g, ""))
  if (!Number.isFinite(points)) {
    return {
      ok: false,
      kind: "invalid",
      field: "points",
      title: "Invalid Points",
      message: "Please enter a valid Points value.",
    }
  }

  const contractsRaw = String(input.contracts).replace(/,/g, "")
  if (contractsRaw.trim() === "") {
    return {
      ok: false,
      kind: "missing",
      field: "contracts",
      message: "Please enter Contracts.",
    }
  }
  const contracts = Number.parseInt(contractsRaw, 10)
  if (!Number.isFinite(contracts)) {
    return {
      ok: false,
      kind: "invalid",
      field: "contracts",
      title: "Invalid Contracts",
      message: "Please enter a valid Contracts value.",
    }
  }

  if (input.rr.trim() !== "" && parseOptionalRr(input.rr) === null) {
    return {
      ok: false,
      kind: "invalid",
      field: "rr",
      title: "Invalid RR",
      message: "Please enter a valid RR value.",
    }
  }

  if (
    input.entryTime &&
    input.exitTime &&
    isExitBeforeEntry(
      input.entryDate,
      input.entryTime,
      input.exitDate,
      input.exitTime
    )
  ) {
    return {
      ok: false,
      kind: "invalid",
      field: "exitTime",
      title: "Invalid Trade Times",
      message: "Exit date and time must be after entry date and time.",
    }
  }

  if (
    tradeFormHasFutureDate({
      entryDate: input.entryDate,
      exitDate: input.exitDate,
    })
  ) {
    return {
      ok: false,
      kind: "invalid",
      field: "entryDate",
      title: "Invalid Trade Date",
      message: "Please select a date that is today or earlier.",
    }
  }

  return { ok: true }
}
