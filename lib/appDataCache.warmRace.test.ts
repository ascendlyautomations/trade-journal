import { describe, it, beforeEach } from "node:test"
import assert from "node:assert/strict"
import {
  TRADES_ANALYTICS_SELECT,
  TRADES_APP_SELECT,
} from "./publicAccountPrivacy.ts"
import {
  INITIAL_TRADES_LIMIT,
  applyBrokerImportedTradeToCache,
  clearAppDataCache,
  ensureTradesLoaded,
  getCachedTrades,
  isAnalyticsHistoryComplete,
  isTradesHistoryComplete,
  setTradesCache,
} from "./appDataCache.ts"
import {
  resetDataPrefetchSession,
  startCriticalDashboardWarm,
} from "./dataPrefetch.ts"

function projectAnalytics(row: Record<string, unknown>) {
  const next: Record<string, unknown> = {}
  for (const key of TRADES_ANALYTICS_SELECT.split(", ")) {
    if (key in row) next[key] = row[key]
  }
  return next
}

function trade(index: number) {
  return {
    id: `t-${index}`,
    user_id: "user-1",
    created_at: new Date(Date.UTC(2026, 0, 1, 0, 0, index)).toISOString(),
    pnl: index + 1,
    notes: `note-${index}`,
    psychology_notes: `psych-${index}`,
    image_url: `https://cdn.example.com/${index}.jpg`,
    import_source: "tradovate",
    entry_time: new Date(Date.UTC(2026, 0, 1, 0, 0, index)).toISOString(),
    exit_time: new Date(Date.UTC(2026, 0, 1, 0, 1, index)).toISOString(),
    rr: 1,
    direction: "Long",
    ticker: "ES",
    strategy: "ORB",
    session: "New York",
    account_id: "acc-1",
    account_name: "Live",
    account_size: "10000",
    account_type: "live",
    mode: "live",
    is_public: false,
    public_description: "",
    duration_seconds: 60,
    points: 1,
    contracts: 1,
    entry_price: 5000,
    exit_price: 5001,
    date: "2026-01-01",
  }
}

type Call = { table: string; select: string; limit: number | null }

function gatedClient(
  rows: ReturnType<typeof trade>[],
  options?: { failWindow?: boolean; failAnalytics?: boolean; failFull?: boolean }
) {
  const calls: Call[] = []
  let releaseWindow: () => void = () => {}
  let releaseAnalytics: () => void = () => {}
  let releaseFull: () => void = () => {}
  const windowGate = new Promise<void>((resolve) => {
    releaseWindow = resolve
  })
  const analyticsGate = new Promise<void>((resolve) => {
    releaseAnalytics = resolve
  })
  const fullGate = new Promise<void>((resolve) => {
    releaseFull = resolve
  })

  const client = {
    calls,
    releaseWindow,
    releaseAnalytics,
    releaseFull,
    from(table: string) {
      return {
        select(select: string) {
          const call: Call = { table, select, limit: null }
          calls.push(call)
          const chain = {
            eq() {
              return chain
            },
            order() {
              return chain
            },
            in() {
              return chain
            },
            limit(n: number) {
              call.limit = n
              return chain
            },
            then(
              onFulfilled: (value: { data: unknown[] | null; error: { message: string } | null }) => unknown,
              onRejected?: (reason: unknown) => unknown
            ) {
              const run = async () => {
                if (table !== "trades") return { data: [], error: null }
                if (select === TRADES_ANALYTICS_SELECT) {
                  await analyticsGate
                  if (options?.failAnalytics) {
                    return { data: null, error: { message: "analytics failed" } }
                  }
                  return { data: rows.map((row) => projectAnalytics(row)), error: null }
                }
                if (call.limit == null) {
                  await fullGate
                  if (options?.failFull) {
                    return { data: null, error: { message: "full failed" } }
                  }
                  return { data: rows, error: null }
                }
                await windowGate
                if (options?.failWindow) {
                  return { data: null, error: { message: "window failed" } }
                }
                return { data: rows.slice(0, call.limit), error: null }
              }
              return run().then(onFulfilled, onRejected)
            },
          }
          return chain
        },
      }
    },
  }
  return client
}

async function flush() {
  for (let i = 0; i < 8; i += 1) {
    await new Promise((resolve) => setTimeout(resolve, 0))
  }
}

function unlimitedJournalSelects(calls: Call[]) {
  return calls.filter(
    (call) =>
      call.table === "trades" &&
      call.select === TRADES_APP_SELECT &&
      call.limit == null
  )
}

function analyticsSelects(calls: Call[]) {
  return calls.filter(
    (call) => call.table === "trades" && call.select === TRADES_ANALYTICS_SELECT
  )
}

describe("trade cache warm race", () => {
  const userId = "user-1"

  beforeEach(() => {
    clearAppDataCache()
    resetDataPrefetchSession()
  })

  it("fresh login warm does not satisfy a dashboard analytics request", async () => {
    const rows = Array.from({ length: 1000 }, (_, index) => trade(index))
    const client = gatedClient(rows)
    startCriticalDashboardWarm(client as never, userId)

    let dashboardSettled = false
    const dashboard = ensureTradesLoaded(client as never, userId, {
      analyticsHistory: true,
    }).then((loaded) => {
      dashboardSettled = true
      return loaded
    })

    await flush()
    assert.equal(dashboardSettled, false)
    client.releaseWindow()
    await flush()

    assert.equal(dashboardSettled, false)
    assert.equal(analyticsSelects(client.calls).length, 1)
    assert.equal(unlimitedJournalSelects(client.calls).length, 0)

    client.releaseAnalytics()
    const loaded = await dashboard
    assert.equal(dashboardSettled, true)
    assert.equal(loaded.length, 1000)
    assert.equal(isAnalyticsHistoryComplete(userId), true)
    assert.equal(isTradesHistoryComplete(userId), false)
    assert.equal(getCachedTrades(userId)?.length, 1000)
    assert.equal(unlimitedJournalSelects(client.calls).length, 0)
    const recent = getCachedTrades(userId)?.find((row) => row.id === "t-0")
    assert.equal(recent?.notes, "note-0")
  })

  it("escalates an in-flight window to full journal and waits", async () => {
    const rows = Array.from({ length: INITIAL_TRADES_LIMIT + 5 }, (_, index) =>
      trade(index)
    )
    const client = gatedClient(rows)
    void ensureTradesLoaded(client as never, userId)
    await flush()

    let fullSettled = false
    const full = ensureTradesLoaded(client as never, userId, {
      fullHistory: true,
    }).then((loaded) => {
      fullSettled = true
      return loaded
    })
    client.releaseWindow()
    await flush()

    assert.equal(fullSettled, false)
    assert.equal(unlimitedJournalSelects(client.calls).length, 1)
    client.releaseFull()
    const loaded = await full
    assert.equal(loaded.length, rows.length)
    assert.equal(isTradesHistoryComplete(userId), true)
    assert.equal(isAnalyticsHistoryComplete(userId), true)
  })

  it("does not treat an in-flight analytics read as full journal history", async () => {
    const rows = Array.from({ length: 1000 }, (_, index) => trade(index))
    const client = gatedClient(rows)
    setTradesCache(userId, rows.slice(0, INITIAL_TRADES_LIMIT), {
      historyComplete: false,
      analyticsHistoryComplete: false,
    })
    const analytics = ensureTradesLoaded(client as never, userId, {
      analyticsHistory: true,
    })
    await flush()
    assert.equal(analyticsSelects(client.calls).length, 1)

    let fullSettled = false
    const full = ensureTradesLoaded(client as never, userId, {
      fullHistory: true,
    }).then((loaded) => {
      fullSettled = true
      return loaded
    })
    client.releaseAnalytics()
    await flush()

    assert.equal(fullSettled, false)
    assert.equal(isTradesHistoryComplete(userId), false)
    assert.equal(unlimitedJournalSelects(client.calls).length, 1)
    client.releaseFull()
    const loaded = await full
    await analytics
    assert.equal(loaded.length, 1000)
    assert.equal(isTradesHistoryComplete(userId), true)
    assert.equal(getCachedTrades(userId)?.find((row) => row.id === "t-500")?.notes, "note-500")
  })

  it("shares one analytics read across callers waiting on the window", async () => {
    const rows = Array.from({ length: 1000 }, (_, index) => trade(index))
    const client = gatedClient(rows)
    void ensureTradesLoaded(client as never, userId)
    const callers = Array.from({ length: 5 }, () =>
      ensureTradesLoaded(client as never, userId, { analyticsHistory: true })
    )
    client.releaseWindow()
    await flush()
    assert.equal(analyticsSelects(client.calls).length, 1)
    client.releaseAnalytics()
    const results = await Promise.all(callers)
    assert.equal(analyticsSelects(client.calls).length, 1)
    assert.equal(unlimitedJournalSelects(client.calls).length, 0)
    for (const result of results) assert.equal(result.length, 1000)
    assert.equal(isAnalyticsHistoryComplete(userId), true)
    assert.equal(isTradesHistoryComplete(userId), false)
  })

  it("shares one full-journal read across callers waiting on analytics", async () => {
    const rows = Array.from({ length: 1000 }, (_, index) => trade(index))
    const client = gatedClient(rows)
    setTradesCache(userId, rows.slice(0, INITIAL_TRADES_LIMIT), {
      historyComplete: false,
      analyticsHistoryComplete: false,
    })
    void ensureTradesLoaded(client as never, userId, { analyticsHistory: true })
    const callers = Array.from({ length: 4 }, () =>
      ensureTradesLoaded(client as never, userId, { fullHistory: true })
    )
    client.releaseAnalytics()
    await flush()
    assert.equal(unlimitedJournalSelects(client.calls).length, 1)
    client.releaseFull()
    const results = await Promise.all(callers)
    assert.equal(unlimitedJournalSelects(client.calls).length, 1)
    for (const result of results) assert.equal(result.length, 1000)
    assert.equal(isTradesHistoryComplete(userId), true)
  })

  it("lets an analytics caller wait for an in-flight full journal read", async () => {
    const rows = Array.from({ length: INITIAL_TRADES_LIMIT + 5 }, (_, index) =>
      trade(index)
    )
    const client = gatedClient(rows)
    setTradesCache(userId, rows.slice(0, INITIAL_TRADES_LIMIT), {
      historyComplete: false,
      analyticsHistoryComplete: false,
    })
    const full = ensureTradesLoaded(client as never, userId, { fullHistory: true })
    await flush()
    const analytics = ensureTradesLoaded(client as never, userId, {
      analyticsHistory: true,
    })
    await flush()
    assert.equal(analyticsSelects(client.calls).length, 0)
    assert.equal(unlimitedJournalSelects(client.calls).length, 1)
    client.releaseFull()
    await Promise.all([full, analytics])
    assert.equal(analyticsSelects(client.calls).length, 0)
    assert.equal(isTradesHistoryComplete(userId), true)
    assert.equal(isAnalyticsHistoryComplete(userId), true)
  })

  it("does not mark analytics complete when the analytics read fails", async () => {
    const rows = Array.from({ length: 1000 }, (_, index) => trade(index))
    const client = gatedClient(rows, { failAnalytics: true })
    void ensureTradesLoaded(client as never, userId)
    const dashboard = ensureTradesLoaded(client as never, userId, {
      analyticsHistory: true,
    })
    client.releaseWindow()
    await flush()
    client.releaseAnalytics()
    const loaded = await dashboard
    assert.equal(loaded.length, INITIAL_TRADES_LIMIT)
    assert.equal(isAnalyticsHistoryComplete(userId), false)
    assert.equal(isTradesHistoryComplete(userId), false)
    assert.equal(getCachedTrades(userId)?.length, INITIAL_TRADES_LIMIT)
    await flush()
    assert.equal(analyticsSelects(client.calls).length, 1)
  })

  it("does not mark full journal complete when that read fails", async () => {
    const rows = Array.from({ length: 1000 }, (_, index) => trade(index))
    const client = gatedClient(rows, { failFull: true })
    setTradesCache(userId, rows.slice(0, INITIAL_TRADES_LIMIT), {
      historyComplete: false,
      analyticsHistoryComplete: false,
    })
    const analytics = ensureTradesLoaded(client as never, userId, {
      analyticsHistory: true,
    })
    const full = ensureTradesLoaded(client as never, userId, { fullHistory: true })
    client.releaseAnalytics()
    await flush()
    client.releaseFull()
    await full
    await analytics
    assert.equal(isAnalyticsHistoryComplete(userId), true)
    assert.equal(isTradesHistoryComplete(userId), false)
    assert.equal(getCachedTrades(userId)?.length, 1000)
    assert.equal(unlimitedJournalSelects(client.calls).length, 1)
  })

  it("keeps a broker insert that arrives while analytics escalates", async () => {
    const rows = Array.from({ length: 1000 }, (_, index) => trade(index))
    const client = gatedClient(rows)
    void ensureTradesLoaded(client as never, userId)
    const dashboard = ensureTradesLoaded(client as never, userId, {
      analyticsHistory: true,
    })
    client.releaseWindow()
    await flush()
    applyBrokerImportedTradeToCache(userId, "INSERT", {
      id: "broker-new",
      pnl: 44,
      created_at: "2026-08-01T15:00:00.000Z",
      import_source: "tradovate",
      ticker: "NQ",
    })
    client.releaseAnalytics()
    await dashboard
    const cached = getCachedTrades(userId) ?? []
    assert.equal(cached.find((row) => row.id === "broker-new")?.pnl, 44)
    assert.equal(cached.find((row) => row.id === "t-0")?.notes, "note-0")
    assert.equal(unlimitedJournalSelects(client.calls).length, 0)
    assert.equal(isTradesHistoryComplete(userId), false)
  })

  it("clears escalated history on logout and does not reuse it for another user", async () => {
    const rows = Array.from({ length: 1000 }, (_, index) => trade(index))
    const client = gatedClient(rows)
    startCriticalDashboardWarm(client as never, userId)
    const dashboard = ensureTradesLoaded(client as never, userId, {
      analyticsHistory: true,
    })
    client.releaseWindow()
    client.releaseAnalytics()
    await dashboard
    assert.equal(getCachedTrades("user-2"), null)
    clearAppDataCache()
    assert.equal(getCachedTrades(userId), null)
    assert.equal(isAnalyticsHistoryComplete(userId), false)
    assert.equal(isTradesHistoryComplete(userId), false)
    assert.equal(getCachedTrades("user-2"), null)
  })
})
