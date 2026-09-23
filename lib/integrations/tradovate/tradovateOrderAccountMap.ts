import type { TradovateFillRaw, TradovateOrderRaw } from "./tradovateFillModels.ts"
import { parseTradovateFillRow } from "./tradovateFillModels.ts"

export function buildTradovateOrderAccountMap(
  orders: TradovateOrderRaw[]
): Map<string, string> {
  const orderAccountById = new Map<string, string>()
  for (const order of orders) {
    if (order.id == null || order.accountId == null) continue
    orderAccountById.set(String(order.id), String(order.accountId))
  }
  return orderAccountById
}

export function missingOrderIdsForTradovateFills(
  fills: TradovateFillRaw[],
  orderAccountById: Map<string, string>
): string[] {
  const missing = new Set<string>()
  for (const fill of fills) {
    if (fill.orderId == null) continue
    const orderId = String(fill.orderId)
    if (!orderAccountById.has(orderId)) missing.add(orderId)
  }
  return [...missing]
}

export function mergeTradovateOrderAccountMap(
  orderAccountById: Map<string, string>,
  orders: TradovateOrderRaw[]
): void {
  for (const order of orders) {
    if (order.id == null || order.accountId == null) continue
    orderAccountById.set(String(order.id), String(order.accountId))
  }
}

export function filterParsedTradovateFillsForAccount(
  fillsRaw: TradovateFillRaw[],
  targetAccountId: string,
  orderAccountById: Map<string, string>
): TradovateFillRaw[] {
  return fillsRaw
    .map(parseTradovateFillRow)
    .filter((row): row is NonNullable<ReturnType<typeof parseTradovateFillRow>> =>
      Boolean(row)
    )
    .filter((fill) => {
      const accountId = orderAccountById.get(String(fill.orderId))
      return accountId === targetAccountId
    })
}
