import type { SupabaseClient } from "@supabase/supabase-js"
import {
  PUBLIC_TRADE_SELECT,
  TRADES_PUBLIC_READ_RELATION,
  sanitizeTradeForViewer,
} from "@/lib/publicAccountPrivacy"
import { asJsonObject } from "@/lib/supabaseProjectedQuery"
import { rpcTradeOwnerRead } from "@/lib/tradeOwnerRead"

/**
 * Resolves a trade row for DM / Trade Room share previews and deep links.
 *
 * Order: owner RPC → `trades_public_read` (public trades) → `trades` social columns
 * (RLS: shared-in-conversation / shared-in-room / shared-in-comment when deployed).
 */
export async function resolveSharedTradeRowForViewer(
  supabase: SupabaseClient,
  tradeId: string,
  viewerUserId?: string | null
): Promise<Record<string, unknown> | null> {
  const id = String(tradeId ?? "").trim()
  if (!id) return null

  const viewerId = viewerUserId?.trim() || null
  let isOwner = false
  if (viewerId) {
    const { data } = await supabase
      .from("trades")
      .select("user_id")
      .eq("id", id)
      .eq("user_id", viewerId)
      .maybeSingle()
    isOwner = data != null
  }

  if (isOwner) {
    const full = await rpcTradeOwnerRead(supabase, id)
    if (full == null) return null
    return sanitizeTradeForViewer(full, { isOwner: true }) ?? null
  }

  const { data: publicData } = await supabase
    .from(TRADES_PUBLIC_READ_RELATION)
    .select(PUBLIC_TRADE_SELECT)
    .eq("id", id)
    .maybeSingle()
    .overrideTypes<Record<string, unknown> | null, { merge: false }>()

  const publicRow = asJsonObject(publicData)
  if (publicRow) {
    return sanitizeTradeForViewer(publicRow, { isOwner: false }) ?? null
  }

  const { data: scopedData } = await supabase
    .from("trades")
    .select(PUBLIC_TRADE_SELECT)
    .eq("id", id)
    .maybeSingle()
    .overrideTypes<Record<string, unknown> | null, { merge: false }>()

  const scopedRow = asJsonObject(scopedData)
  return scopedRow
    ? sanitizeTradeForViewer(scopedRow, { isOwner: false }) ?? null
    : null
}