import { isCopyTradedMode } from "./tradeMode.ts"

export type CopyTradeModeCounts = {
  live: number
  funded: number
  eval: number
  sim: number
  backtest: number
}

export type CopyTradeWireRow = {
  id?: unknown
  user_id?: unknown
  trade_mode?: unknown
  copied_account_ids?: unknown
  copy_trading_group_id?: unknown
  source_account_id?: unknown
  account_id?: unknown
  account_type?: unknown
  account_name?: unknown
  account_size?: unknown
  account_number?: unknown
  /** Profile copy linkage — authoritative `accounts.mode` for this row. */
  account_mode?: unknown
  mode?: unknown
  created_at?: unknown
  entry_time?: unknown
  trade_date?: unknown
  ticker?: unknown
}

const MODE_ORDER = ["live", "funded", "eval", "sim", "backtest"] as const

function normalizeMode(raw: unknown): keyof CopyTradeModeCounts | null {
  const norm = String(raw ?? "")
    .trim()
    .toLowerCase()
  if (!norm) return null
  if (norm === "evaluation") return "eval"
  if (norm === "live" || norm === "personal" || norm === "broker") return "live"
  if (norm === "funded") return "funded"
  if (norm === "eval") return "eval"
  if (norm === "sim" || norm === "replay") return "sim"
  if (norm === "backtest") return "backtest"
  return null
}

export function copyTradeParticipatingAccountIds(
  trade: CopyTradeWireRow | null | undefined
): string[] {
  if (!trade) return []
  const rowAccount = String(trade.account_id ?? "").trim()
  if (!isCopyTradedMode(trade)) {
    return rowAccount ? [rowAccount] : []
  }
  const source = String(trade.source_account_id ?? rowAccount ?? "").trim()
  const copied = Array.isArray(trade.copied_account_ids)
    ? trade.copied_account_ids
        .map((id) => String(id ?? "").trim())
        .filter(Boolean)
    : []
  const ids = new Set<string>()
  if (source) ids.add(source)
  for (const id of copied) ids.add(id)
  if (rowAccount) ids.add(rowAccount)
  return [...ids]
}

function hasAuthoritativeCopyStamp(trade: CopyTradeWireRow): boolean {
  const source = String(trade.source_account_id ?? "").trim()
  const copied = Array.isArray(trade.copied_account_ids)
    ? trade.copied_account_ids
        .map((id) => String(id ?? "").trim())
        .filter(Boolean)
    : []
  return Boolean(source && copied.length > 0)
}

/** Stable key for one copy-trade journal action (sibling rows share this). */
export function copyTradeBatchKey(
  trade: CopyTradeWireRow | null | undefined
): string | null {
  if (!trade || !isCopyTradedMode(trade)) return null
  const userId = String(trade.user_id ?? "").trim()
  const source = String(trade.source_account_id ?? trade.account_id ?? "").trim()
  const copied = [...copyTradeParticipatingAccountIds(trade)].sort().join(",")
  const ticker = String(trade.ticker ?? "").trim().toLowerCase()
  const entry = String(trade.entry_time ?? trade.trade_date ?? "").trim()
  if (!userId) return null

  // Historical fanout rows share source + copied_account_ids + entry — not always identical created_at.
  if (hasAuthoritativeCopyStamp(trade)) {
    if (!entry) return null
    return `${userId}|${source}|${copied}|${ticker}|${entry}`
  }

  const created = String(trade.created_at ?? "").trim().slice(0, 19)
  if (!created) return null
  return `${userId}|${source}|${copied}|${ticker}|${entry}|${created}`
}

/** Trade join on feed posts — merges post author when trade.user_id is omitted. */
export function copyTradeWireFromFeedPost(post: {
  user_id?: unknown
  trades?: unknown
}): CopyTradeWireRow | null {
  const t = post?.trades
  if (!t) return null
  const row = Array.isArray(t) ? t[0] : t
  if (!row || typeof row !== "object") return null
  const trade = row as CopyTradeWireRow
  const postUser = String(post.user_id ?? "").trim()
  if (!String(trade.user_id ?? "").trim() && postUser) {
    return { ...trade, user_id: postUser }
  }
  return trade
}

export function accumulateCopyTradeModeCounts(
  trades: readonly CopyTradeWireRow[]
): CopyTradeModeCounts {
  const counts: CopyTradeModeCounts = {
    live: 0,
    funded: 0,
    eval: 0,
    sim: 0,
    backtest: 0,
  }
  const seenAccounts = new Set<string>()
  for (const trade of trades) {
    const accountId = String(trade.account_id ?? "").trim()
    if (!accountId || seenAccounts.has(accountId)) continue
    seenAccounts.add(accountId)
    const modeKey = normalizeMode(
      trade.account_mode ?? trade.account_type ?? trade.mode
    )
    if (!modeKey) continue
    counts[modeKey] += 1
  }
  return counts
}

function modeCountLabel(mode: keyof CopyTradeModeCounts, count: number): string {
  const label =
    mode === "eval"
      ? count === 1
        ? "Eval"
        : "Eval"
      : mode === "live"
        ? "Live"
        : mode === "funded"
          ? "Funded"
          : mode === "sim"
            ? "Sim"
            : "Backtest"
  return `${count} ${label}`
}

function formatCopyTradeModeCountSegment(
  counts: CopyTradeModeCounts
): string | null {
  const parts: string[] = []
  for (const mode of MODE_ORDER) {
    const n = counts[mode]
    if (n <= 0) continue
    parts.push(modeCountLabel(mode, n))
  }
  if (parts.length === 0) return null
  return parts.join(" • ")
}

/** Public social line: `Copy Traded across 3 accounts • 1 Live • 2 Funded` */
export function formatCopyTradePublicModeSummary(
  counts: CopyTradeModeCounts,
  participatingAccountCount?: number
): string | null {
  const modeSegment = formatCopyTradeModeCountSegment(counts)
  if (participatingAccountCount != null && participatingAccountCount > 0) {
    const noun =
      participatingAccountCount === 1 ? "account" : "accounts"
    const prefix = `Copy Traded across ${participatingAccountCount} ${noun}`
    return modeSegment ? `${prefix} • ${modeSegment}` : prefix
  }
  if (!modeSegment) return null
  return `Copy Traded on ${modeSegment}`
}

export function formatCopyTradePublicModeSummaryFromTrades(
  trades: readonly CopyTradeWireRow[]
): string | null {
  if (trades.length === 0) return null
  const counts = accumulateCopyTradeModeCounts(trades)
  const participating = new Set<string>()
  for (const trade of trades) {
    for (const id of copyTradeParticipatingAccountIds(trade)) {
      participating.add(id)
    }
  }
  const accountCount = participating.size
  return formatCopyTradePublicModeSummary(
    counts,
    accountCount > 0 ? accountCount : undefined
  )
}

export function indexCopyTradeBatchMembers(
  trades: readonly CopyTradeWireRow[]
): Map<string, CopyTradeWireRow[]> {
  const map = new Map<string, CopyTradeWireRow[]>()
  for (const trade of trades) {
    const key = copyTradeBatchKey(trade)
    if (!key) continue
    const bucket = map.get(key)
    if (bucket) bucket.push(trade)
    else map.set(key, [trade])
  }
  return map
}

export type TradesPageListItem =
  | { kind: "single"; trade: CopyTradeWireRow }
  | {
      kind: "copyGroup"
      batchKey: string
      representative: CopyTradeWireRow
      members: CopyTradeWireRow[]
      modeSummary: string | null
    }

/** One card per copy action; normal trades unchanged. */
export function groupTradesForTradesPageDisplay(
  trades: readonly CopyTradeWireRow[]
): TradesPageListItem[] {
  const batchIndex = indexCopyTradeBatchMembers(trades)
  const consumed = new Set<string>()
  const out: TradesPageListItem[] = []

  for (const trade of trades) {
    const tradeId = String(trade.id ?? "").trim()
    const batchKey = copyTradeBatchKey(trade)
    if (!batchKey) {
      out.push({ kind: "single", trade })
      continue
    }
    if (consumed.has(batchKey)) continue
    consumed.add(batchKey)
    const members = batchIndex.get(batchKey) ?? [trade]
    const representative =
      members.find(
        (row) =>
          String(row.source_account_id ?? "").trim() ===
          String(row.account_id ?? "").trim()
      ) ?? members[0]
    out.push({
      kind: "copyGroup",
      batchKey,
      representative,
      members,
      modeSummary: formatCopyTradePublicModeSummaryFromTrades(members),
    })
  }

  return out
}

export function tradeMatchesParticipatingAccountFilter(
  trade: CopyTradeWireRow,
  accountFilter: string
): boolean {
  if (!accountFilter || accountFilter === "all") return true
  const participating = copyTradeParticipatingAccountIds(trade)
  if (participating.length === 0) {
    return String(trade.account_id ?? "").trim() === accountFilter
  }
  return participating.includes(accountFilter)
}

export function dedupeCopyTradeFeedPosts<T extends { id?: unknown; trades?: unknown }>(
  posts: readonly T[]
): T[] {
  const seenBatch = new Set<string>()
  const out: T[] = []

  for (const post of posts) {
    const trade = postTradeJoinFromPost(post)
    const batchKey = copyTradeBatchKey(trade)
    if (!batchKey) {
      out.push(post)
      continue
    }
    if (seenBatch.has(batchKey)) continue
    seenBatch.add(batchKey)
    out.push(post)
  }

  return out
}

function postTradeJoinFromPost(post: {
  user_id?: unknown
  trades?: unknown
}): CopyTradeWireRow | null {
  return copyTradeWireFromFeedPost(post)
}

export function attachCopyTradeSummariesToPosts<
  T extends { trades?: unknown; copy_trade_mode_summary?: string },
>(
  posts: readonly T[],
  batchMembers: Map<string, CopyTradeWireRow[]>
): T[] {
  return posts.map((post) => {
    const trade = postTradeJoinFromPost(post)
    const key = copyTradeBatchKey(trade)
    if (!key) return post
    const members = batchMembers.get(key)
    if (!members || members.length === 0) return post
    const summary = formatCopyTradePublicModeSummaryFromTrades(members)
    if (!summary) return post
    return { ...post, copy_trade_mode_summary: summary }
  })
}
