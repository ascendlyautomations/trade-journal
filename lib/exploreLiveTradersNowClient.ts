import type { ExploreLiveTraderNow } from "./livekit/exploreLiveTradersNow.ts"

export type { ExploreLiveTraderNow }

export class ExploreLiveTradersFetchError extends Error {
  readonly status: number

  constructor(status: number, message = "Could not load live traders.") {
    super(message)
    this.name = "ExploreLiveTradersFetchError"
    this.status = status
  }
}

export async function fetchExploreLiveTradersNow(
  limit = 12
): Promise<ExploreLiveTraderNow[]> {
  const res = await fetch(
    `/api/explore/live-traders?limit=${encodeURIComponent(String(limit))}`,
    { credentials: "include", cache: "no-store" }
  )
  let payload: { items?: ExploreLiveTraderNow[] } | null = null
  try {
    payload = (await res.json()) as { items?: ExploreLiveTraderNow[] }
  } catch {
    payload = null
  }
  if (!res.ok) {
    throw new ExploreLiveTradersFetchError(res.status)
  }
  return Array.isArray(payload?.items) ? payload.items : []
}
