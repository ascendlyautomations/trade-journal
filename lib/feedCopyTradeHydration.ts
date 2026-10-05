import type { SupabaseClient } from "@supabase/supabase-js"
import {
  attachCopyTradeSummariesToPosts,
  copyTradeWireFromFeedPost,
  indexCopyTradeBatchMembers,
  type CopyTradeWireRow,
} from "./copyTradePresentation"
import { isCopyTradedMode } from "./tradeMode"

function copiedIdsEqual(a: unknown, b: readonly string[]): boolean {
  const left = Array.isArray(a)
    ? a.map((id) => String(id ?? "").trim()).filter(Boolean).sort()
    : []
  const right = [...b].map((id) => id.trim()).filter(Boolean).sort()
  if (left.length !== right.length) return false
  return left.every((id, i) => id === right[i])
}

type CopyLinkageSignature = {
  userId: string
  source: string
  ticker: string
  entry: string
  copied: string[]
}

/** Loads sibling copy-trade rows for feed posts and attaches public mode summaries. */
export async function hydrateCopyTradeFeedPosts<
  T extends { id?: unknown; user_id?: unknown; trades?: unknown },
>(client: SupabaseClient, posts: T[]): Promise<T[]> {
  const signatures = new Map<string, CopyLinkageSignature>()

  for (const post of posts) {
    const trade = copyTradeWireFromFeedPost(post)
    if (trade == null || !isCopyTradedMode(trade)) continue
    const userId = String(trade.user_id ?? post.user_id ?? "").trim()
    const source = String(trade.source_account_id ?? trade.account_id ?? "").trim()
    const copied = Array.isArray(trade.copied_account_ids)
      ? trade.copied_account_ids
          .map((id) => String(id ?? "").trim())
          .filter(Boolean)
      : []
    if (!userId || !source || copied.length === 0) continue
    const ticker = String(trade.ticker ?? "").trim()
    const entry = String(trade.entry_time ?? trade.trade_date ?? "").trim()
    if (!entry) continue
    const key = `${userId}|${source}|${copied.sort().join(",")}|${ticker.toLowerCase()}|${entry}`
    if (!signatures.has(key)) {
      signatures.set(key, { userId, source, ticker, entry, copied })
    }
  }

  if (signatures.size === 0) return posts

  const allMembers: CopyTradeWireRow[] = []

  for (const sig of signatures.values()) {
    let query = client
      .from("trades")
      .select(
        "id, user_id, trade_mode, mode, account_type, account_id, source_account_id, copied_account_ids, copy_trading_group_id, created_at, entry_time, trade_date, ticker"
      )
      .eq("user_id", sig.userId)
      .eq("trade_mode", "copy_traded")
      .eq("source_account_id", sig.source)
      .eq("ticker", sig.ticker)
      .eq("entry_time", sig.entry)

    const { data, error } = await query
    if (error || !data?.length) continue

    for (const row of data as CopyTradeWireRow[]) {
      if (copiedIdsEqual(row.copied_account_ids, sig.copied)) {
        allMembers.push(row)
      }
    }
  }

  if (allMembers.length === 0) return posts

  const batchMembers = indexCopyTradeBatchMembers(allMembers)
  return attachCopyTradeSummariesToPosts(posts, batchMembers)
}
