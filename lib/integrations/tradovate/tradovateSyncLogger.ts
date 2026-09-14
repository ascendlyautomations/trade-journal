export type TradovateSyncLogContext = {
  connectionId?: string
  mappingId?: string
  userId?: string
  provider?: string
  trigger?: string
  eventCategory?: string
  durationMs?: number
  fetched?: number
  newExecutions?: number
  tradesCreated?: number
  tradesUpdated?: number
  coalesced?: boolean
  reconnectCount?: number
  errorCode?: string
}

export function logTradovateSync(
  message: string,
  context: TradovateSyncLogContext = {}
): void {
  console.info(
    JSON.stringify({
      scope: "tradovate_sync",
      message,
      ...context,
    })
  )
}
