export type TradovatePropsEvent = {
  entityType: string
  eventType: string
  entity: Record<string, unknown>
}

/** Entity types that should trigger REST reconciliation (events are not ingested directly). */
export function tradovatePropsEventTriggersSync(entityType: string): boolean {
  const t = entityType.trim().toLowerCase()
  return t === "fill" || t === "order" || t === "executionreport"
}

export function resolveExternalAccountIdFromPropsEvent(
  event: TradovatePropsEvent,
  orderAccountById: Map<string, string>
): string | null {
  const entity = event.entity
  if (entity.accountId != null) return String(entity.accountId)
  const orderId = entity.orderId
  if (orderId != null) {
    const hit = orderAccountById.get(String(orderId))
    if (hit) return hit
  }
  return null
}
