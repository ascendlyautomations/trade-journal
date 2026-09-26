import { describe, it, beforeEach } from "node:test"
import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"
import {
  TRADES_ANALYTICS_EXCLUDED_HEAVY_FIELDS,
  TRADES_ANALYTICS_FIELDS,
  TRADES_ANALYTICS_SELECT,
  TRADES_APP_SELECT,
} from "./publicAccountPrivacy.ts"
import {
  INITIAL_TRADES_LIMIT,
  applyBrokerImportedTradeToCache,
  clearAppDataCache,
  ensureAnalyticsTradesHistory,
  ensureFullTradesHistory,
  ensureRichTradeRowsByIds,
  ensureTradesLoaded,
  fullJournalRemainsComplete,
  getCachedTrades,
  isAnalyticsHistoryComplete,
  isTradesHistoryComplete,
  mergeAnalyticsSnapshot,
  setTradesCache,
} from "./appDataCache.ts"

const root = path.dirname(fileURLToPath(import.meta.url))

function projectAnalytics(row: Record<string, unknown>) {
  const next: Record<string, unknown> = {}
  for (const key of TRADES_ANALYTICS_FIELDS) {
    if (key in row) next[key] = row[key]
  }
  return next
}

function richTrade(index: number) {
  const created = new Date(Date.UTC(2026, 0, 1, 15, index % 24, index % 60)).toISOString()
  return {
    id: `t-${index}`,
    user_id: "user-1",
    created_at: created,
    date: "2026-01-01",
    entry_time: created,
    exit_time: created,
    pnl: index % 2 === 0 ? 50 : -20,
    rr: 1.5,
    direction: index % 2 === 0 ? "Long" : "Short",
    ticker: "ES",
    strategy: "ORB",
    session: "New York",
    account_id: "acc-1",
    account_name: "Eval",
    account_size: "50000",
    account_type: "eval",
    mode: "eval",
    is_public: index % 5 === 0,
    public_description: index % 5 === 0 ? "Shared recap" : "",
    duration_seconds: 120,
    points: 4,
    contracts: 2,
    entry_price: 5000,
    exit_price: 5004,
    notes: `journal note ${index} ${"n".repeat(80)}`,
    psychology_notes: `psych ${index}`,
    image_url: `https://cdn.example.com/shots/${index}.jpg`,
    import_source: "tradovate",
  }
}

function tradesClient(
  allRich: ReturnType<typeof richTrade>[],
  options?: { gateAnalytics?: boolean; gateFull?: boolean }
) {
  const calls: { select: string; limit: number | null }[] = []
  let releaseAnalytics: (() => void) | null = null
  let releaseFull: (() => void) | null = null
  const analyticsGate = options?.gateAnalytics
    ? new Promise<void>((resolve) => {
        releaseAnalytics = resolve
      })
    : null
  const fullGate = options?.gateFull
    ? new Promise<void>((resolve) => {
        releaseFull = resolve
      })
    : null

  const client = {
    calls,
    releaseAnalytics: () => releaseAnalytics?.(),
    releaseFull: () => releaseFull?.(),
    from() {
      return {
        select(select: string) {
          const call = { select, limit: null as number | null, ids: null as string[] | null }
          calls.push(call)
          const chain: {
            eq: () => typeof chain
            order: () => typeof chain
            in: (column: string, ids: string[]) => typeof chain
            limit: (n: number) => typeof chain
            then: (
              onFulfilled: (value: { data: unknown[]; error: null }) => unknown,
              onRejected?: (reason: unknown) => unknown
            ) => Promise<unknown>
          } = {
            eq() {
              return chain
            },
            order() {
              return chain
            },
            in(_column: string, ids: string[]) {
              call.ids = ids
              return chain
            },
            limit(n: number) {
              call.limit = n
              return chain
            },
            then(onFulfilled, onRejected) {
              const finish = () => {
                let rows =
                  call.select === TRADES_ANALYTICS_SELECT
                    ? allRich.map((row) => projectAnalytics(row))
                    : allRich
                if (call.ids) {
                  const ids = new Set(call.ids)
                  rows = rows.filter((row) => ids.has(String(row.id)))
                }
                const data = call.limit != null ? rows.slice(0, call.limit) : rows
                return { data, error: null as null }
              }
              let pending = Promise.resolve()
              if (call.select === TRADES_ANALYTICS_SELECT && analyticsGate) {
                pending = analyticsGate
              }
              if (
                call.select === TRADES_APP_SELECT &&
                call.limit == null &&
                fullGate
              ) {
                pending = fullGate
              }
              return pending.then(finish).then(onFulfilled, onRejected)
            },
          }
          return chain
        },
      }
    },
  }
  return client
}

async function flushInFlight() {
  for (let i = 0; i < 10; i += 1) {
    await new Promise((resolve) => setTimeout(resolve, 0))
  }
}

describe("analytics trade history", () => {
  const userId = "user-1"

  beforeEach(() => {
    clearAppDataCache()
  })

  it("keeps analytics completeness independent from full journal completeness", () => {
    setTradesCache(
      userId,
      [projectAnalytics(richTrade(1))],
      { historyComplete: false, analyticsHistoryComplete: true }
    )
    assert.equal(isAnalyticsHistoryComplete(userId), true)
    assert.equal(isTradesHistoryComplete(userId), false)
  })

  it("preserves rich journal fields when a narrow snapshot merges", () => {
    const rich = richTrade(1)
    const narrow = projectAnalytics({ ...rich, pnl: 77 })
    const [merged] = mergeAnalyticsSnapshot([rich], [narrow])
    assert.equal(merged.pnl, 77)
    assert.equal(merged.notes, rich.notes)
    assert.equal(merged.psychology_notes, rich.psychology_notes)
    assert.equal(merged.image_url, rich.image_url)
    assert.equal("notes" in narrow, false)
  })

  it("drops full-journal completeness when a narrow snapshot adds an id", () => {
    const existing = [richTrade(1)]
    assert.equal(
      fullJournalRemainsComplete(existing, [projectAnalytics(richTrade(1))], true),
      true
    )
    assert.equal(
      fullJournalRemainsComplete(
        existing,
        [projectAnalytics(richTrade(1)), projectAnalytics(richTrade(2))],
        true
      ),
      false
    )
  })

  it("dashboard load fetches a rich window then narrow history, not the full journal", async () => {
    const rows = Array.from({ length: INITIAL_TRADES_LIMIT + 1 }, (_, index) =>
      richTrade(index)
    )
    const client = tradesClient(rows)
    await ensureTradesLoaded(client as never, userId, { analyticsHistory: true })
    await flushInFlight()

    assert.equal(isAnalyticsHistoryComplete(userId), true)
    assert.equal(isTradesHistoryComplete(userId), false)
    assert.equal(getCachedTrades(userId)?.length, rows.length)
    assert.equal(
      client.calls.filter((call) => call.select === TRADES_APP_SELECT && call.limit == null)
        .length,
      0
    )
    assert.equal(
      client.calls.filter((call) => call.select === TRADES_ANALYTICS_SELECT).length,
      1
    )
    assert.ok(client.calls.some((call) => call.select === TRADES_APP_SELECT && call.limit === INITIAL_TRADES_LIMIT))
    const newest = getCachedTrades(userId)?.find((row) => row.id === "t-0")
    const oldest = getCachedTrades(userId)?.find((row) => row.id === `t-${INITIAL_TRADES_LIMIT}`)
    assert.equal(newest?.notes, rows[0].notes)
    assert.equal(oldest?.notes, undefined)
    assert.equal(oldest?.pnl, rows[INITIAL_TRADES_LIMIT].pnl)
  })

  it("opening trades after analytics history loads the full journal once", async () => {
    const rows = Array.from({ length: INITIAL_TRADES_LIMIT + 1 }, (_, index) =>
      richTrade(index)
    )
    const client = tradesClient(rows)
    await ensureTradesLoaded(client as never, userId, { analyticsHistory: true })
    await flushInFlight()
    const before = client.calls.length

    await ensureTradesLoaded(client as never, userId, { fullHistory: true })
    await flushInFlight()

    const fullSelects = client.calls
      .slice(before)
      .filter((call) => call.select === TRADES_APP_SELECT && call.limit == null)
    assert.equal(fullSelects.length, 1)
    assert.equal(isTradesHistoryComplete(userId), true)
    assert.equal(isAnalyticsHistoryComplete(userId), true)
    const oldest = getCachedTrades(userId)?.find((row) => row.id === `t-${INITIAL_TRADES_LIMIT}`)
    assert.equal(oldest?.notes, rows[INITIAL_TRADES_LIMIT].notes)
    assert.equal(oldest?.image_url, rows[INITIAL_TRADES_LIMIT].image_url)
  })

  it("does not treat analytics history as enough for a second trades open", async () => {
    const rows = Array.from({ length: INITIAL_TRADES_LIMIT + 1 }, (_, index) =>
      richTrade(index)
    )
    const client = tradesClient(rows)
    await ensureTradesLoaded(client as never, userId, { analyticsHistory: true })
    await flushInFlight()
    await ensureFullTradesHistory(client as never, userId)
    const callsAfterFull = client.calls.length
    await ensureFullTradesHistory(client as never, userId)
    assert.equal(client.calls.length, callsAfterFull)
  })

  it("patches a broker insert during an analytics read without a full reload", async () => {
    const rows = Array.from({ length: INITIAL_TRADES_LIMIT + 1 }, (_, index) =>
      richTrade(index)
    )
    const client = tradesClient(rows, { gateAnalytics: true })
    const load = ensureTradesLoaded(client as never, userId, {
      analyticsHistory: true,
      force: true,
    })
    await flushInFlight()
    applyBrokerImportedTradeToCache(userId, "INSERT", {
      id: "broker-new",
      pnl: 33,
      created_at: "2026-06-01T15:00:00.000Z",
      import_source: "tradovate",
      ticker: "NQ",
    })
    client.releaseAnalytics()
    await load

    const cached = getCachedTrades(userId) ?? []
    assert.equal(cached.find((row) => row.id === "broker-new")?.pnl, 33)
    assert.equal(cached.find((row) => row.id === "t-0")?.notes, rows[0].notes)
    assert.equal(
      client.calls.filter((call) => call.select === TRADES_APP_SELECT && call.limit == null)
        .length,
      0
    )
    assert.equal(isTradesHistoryComplete(userId), false)
    assert.equal(isAnalyticsHistoryComplete(userId), true)
  })

  it("patches a broker update and delete during a full-journal read", async () => {
    const rows = Array.from({ length: 3 }, (_, index) => richTrade(index))
    setTradesCache(userId, rows, {
      historyComplete: false,
      analyticsHistoryComplete: true,
    })
    const client = tradesClient(rows, { gateFull: true })
    const load = ensureFullTradesHistory(client as never, userId)
    await flushInFlight()
    applyBrokerImportedTradeToCache(userId, "UPDATE", {
      id: "t-0",
      pnl: 999,
      import_source: "tradovate",
    })
    applyBrokerImportedTradeToCache(userId, "DELETE", null, {
      id: "t-1",
      import_source: "tradovate",
    })
    client.releaseFull()
    await load

    const cached = getCachedTrades(userId) ?? []
    assert.equal(cached.find((row) => row.id === "t-0")?.pnl, 999)
    assert.equal(cached.find((row) => row.id === "t-0")?.notes, rows[0].notes)
    assert.equal(cached.find((row) => row.id === "t-1"), undefined)
    assert.equal(isTradesHistoryComplete(userId), true)
  })

  it("keeps a broker update on an analytics-complete cache without reloading", () => {
    setTradesCache(
      userId,
      [projectAnalytics(richTrade(1))],
      { historyComplete: false, analyticsHistoryComplete: true }
    )
    applyBrokerImportedTradeToCache(userId, "UPDATE", {
      id: "t-1",
      pnl: 12,
      import_source: "rithmic",
    })
    applyBrokerImportedTradeToCache(userId, "DELETE", null, {
      id: "t-1",
      import_source: "rithmic",
    })
    assert.equal(getCachedTrades(userId)?.length, 0)
    assert.equal(isAnalyticsHistoryComplete(userId), true)
    assert.equal(isTradesHistoryComplete(userId), false)
  })

  it("clears both histories on logout and does not reuse them for another user", () => {
    setTradesCache(userId, [richTrade(1)], {
      historyComplete: true,
      analyticsHistoryComplete: true,
    })
    setTradesCache("user-2", [richTrade(2)], {
      historyComplete: false,
      analyticsHistoryComplete: true,
    })
    clearAppDataCache()
    assert.equal(getCachedTrades(userId), null)
    assert.equal(getCachedTrades("user-2"), null)
    assert.equal(isTradesHistoryComplete(userId), false)
    assert.equal(isAnalyticsHistoryComplete("user-2"), false)
  })

  it("dashboard refresh reloads narrow history and keeps an existing full journal", async () => {
    const rows = Array.from({ length: INITIAL_TRADES_LIMIT + 1 }, (_, index) =>
      richTrade(index)
    )
    setTradesCache(userId, rows, {
      historyComplete: true,
      analyticsHistoryComplete: true,
    })
    const client = tradesClient(rows)
    await ensureTradesLoaded(client as never, userId, {
      force: true,
      analyticsHistory: true,
    })

    assert.equal(
      client.calls.filter((call) => call.select === TRADES_APP_SELECT && call.limit == null)
        .length,
      0
    )
    assert.equal(
      client.calls.filter((call) => call.select === TRADES_ANALYTICS_SELECT).length,
      1
    )
    assert.equal(isTradesHistoryComplete(userId), true)
    const oldest = getCachedTrades(userId)?.find((row) => row.id === `t-${INITIAL_TRADES_LIMIT}`)
    assert.equal(oldest?.notes, rows[INITIAL_TRADES_LIMIT].notes)
    assert.equal(oldest?.psychology_notes, rows[INITIAL_TRADES_LIMIT].psychology_notes)
  })

  it("enriches only the requested ids with journal columns", async () => {
    const rows = [richTrade(1), richTrade(2)]
    setTradesCache(
      userId,
      rows.map((row) => projectAnalytics(row)),
      { historyComplete: false, analyticsHistoryComplete: true }
    )
    const client = tradesClient(rows)
    await ensureRichTradeRowsByIds(client as never, userId, ["t-1"])
    const cached = getCachedTrades(userId) ?? []
    assert.equal(cached.find((row) => row.id === "t-1")?.notes, rows[0].notes)
    assert.equal(cached.find((row) => row.id === "t-2")?.notes, undefined)
    assert.equal(isTradesHistoryComplete(userId), false)
    assert.equal(cached.length, 2)
  })

  it("wires dashboard and calendar to analytics history and leaves trades and analyst on the full journal", () => {
    const dashboard = fs.readFileSync(path.join(root, "../app/(app)/dashboard/page.tsx"), "utf8")
    const calendar = fs.readFileSync(path.join(root, "../app/calendar/page.tsx"), "utf8")
    const trades = fs.readFileSync(path.join(root, "../app/(app)/trades/page.tsx"), "utf8")
    const analyst = fs.readFileSync(path.join(root, "../app/analyst/page.tsx"), "utf8")
    const streaks = fs.readFileSync(path.join(root, "userStreaksCache.ts"), "utf8")
    const flags = fs.readFileSync(path.join(root, "backendV2/flags.ts"), "utf8")
    const broker = fs.readFileSync(path.join(root, "useBrokerImportedTradesRealtime.ts"), "utf8")

    assert.match(dashboard, /analyticsHistory:\s*true/)
    assert.doesNotMatch(dashboard, /fullHistory:\s*true/)
    assert.match(calendar, /analyticsHistory:\s*true/)
    assert.doesNotMatch(calendar, /fullHistory:\s*true/)
    assert.match(trades, /fullHistory:\s*true/)
    assert.match(analyst, /fullHistory:\s*true/)
    assert.match(analyst, /psychology_notes/)
    assert.match(analyst, /image_url/)
    assert.match(streaks, /ensureAnalyticsTradesHistory/)
    assert.doesNotMatch(streaks, /ensureFullTradesHistory/)
    assert.match(streaks, /from\("profile_posts"\)/)
    assert.match(streaks, /from\("reels"\)/)
    assert.match(flags, /dashboard:\s*false/)
    assert.match(flags, /feed:\s*true/)
    assert.match(flags, /messages:\s*true/)
    assert.match(broker, /applyBrokerImportedTradeToCache/)
    assert.doesNotMatch(broker, /fullHistory/)
    assert.doesNotMatch(broker, /analyticsHistory/)
  })

  it("analytics projection includes required fields and excludes heavyweight journal fields", () => {
    for (const field of [
      "id",
      "user_id",
      "created_at",
      "date",
      "entry_time",
      "exit_time",
      "pnl",
      "rr",
      "direction",
      "ticker",
      "strategy",
      "session",
      "account_id",
      "account_name",
      "account_size",
      "account_type",
      "mode",
      "is_public",
      "public_description",
      "duration_seconds",
      "points",
      "contracts",
      "entry_price",
      "exit_price",
    ]) {
      assert.ok(TRADES_ANALYTICS_FIELDS.includes(field as never), field)
    }
    for (const field of TRADES_ANALYTICS_EXCLUDED_HEAVY_FIELDS) {
      assert.equal(TRADES_ANALYTICS_FIELDS.includes(field as never), false)
    }
    assert.equal(TRADES_APP_SELECT.includes("notes"), true)
    assert.equal(TRADES_ANALYTICS_SELECT.includes("notes"), false)
    assert.equal(TRADES_ANALYTICS_SELECT.includes("image_url"), false)
    assert.equal(TRADES_ANALYTICS_SELECT.includes("psychology_notes"), false)
    assert.equal(TRADES_APP_SELECT.split(",").length > TRADES_ANALYTICS_FIELDS.length, true)
  })
})
