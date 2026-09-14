export type TradovateFillRaw = {
  id?: number | string
  orderId?: number | string
  contractId?: number | string
  timestamp?: string
  tradeDate?: unknown
  action?: string
  qty?: number
  price?: number
  active?: boolean
  finallyPaired?: number
}

export type TradovateOrderRaw = {
  id?: number | string
  accountId?: number | string
  contractId?: number | string
}

export type TradovateContractRaw = {
  id?: number | string
  name?: string
  contractMaturityId?: number | string
}

export type TradovateContractMaturityRaw = {
  id?: number | string
  productId?: number | string
}

export type TradovateProductRaw = {
  id?: number | string
  name?: string
  valuePerPoint?: number
}

export type TradovateFillFeeRaw = {
  id?: number | string
  clearingFee?: number
  exchangeFee?: number
  nfaFee?: number
  commission?: number
}

export function parseTradovateFillRow(raw: unknown): TradovateFillRaw | null {
  if (!raw || typeof raw !== "object") return null
  const row = raw as TradovateFillRaw
  if (row.id == null || row.contractId == null || row.orderId == null) return null
  if (!row.timestamp || !row.action || row.qty == null || row.price == null) return null
  const action = String(row.action).trim()
  if (action !== "Buy" && action !== "Sell") return null
  const qty = Number(row.qty)
  const price = Number(row.price)
  if (!Number.isFinite(qty) || qty <= 0 || !Number.isFinite(price)) return null
  return row
}

export function tradovateFillStableId(raw: TradovateFillRaw): string {
  return String(raw.id)
}

export function tradovateSide(raw: TradovateFillRaw): "Buy" | "Sell" {
  return String(raw.action).trim() === "Sell" ? "Sell" : "Buy"
}
