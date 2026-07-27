import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"

export const LIKE_FOLLOW_BATCH_WINDOW_MS = 45_000
export const ROOM_DIGEST_COOLDOWN_MS = 120_000

export type PushBatchKind = "like" | "follow" | "room_digest" | "dm"

/** DM batch windows stay open until the conversation is read (not flushed by cron). */
export const DM_PUSH_BATCH_TTL_MS = 7 * 24 * 60 * 60 * 1000

/** Stable APNs thread-id / collapse-id for one DM conversation. */
export function dmPushThreadId(conversationId: string): string {
  return `dm:${conversationId}`
}

export type PushBatchRow = {
  recipient_user_id: string
  batch_kind: PushBatchKind
  batch_key: string
  window_ends_at: string
  meta: Record<string, unknown>
  created_at: string
  updated_at: string
}

export async function getOpenBatch(
  recipientUserId: string,
  batchKind: PushBatchKind,
  batchKey: string
): Promise<PushBatchRow | null> {
  const { data, error } = await supabaseServiceRole
    .from("push_batch_windows")
    .select("*")
    .eq("recipient_user_id", recipientUserId)
    .eq("batch_kind", batchKind)
    .eq("batch_key", batchKey)
    .maybeSingle()

  if (error) {
    console.error("[push-batch] getOpenBatch failed", error)
    return null
  }
  return (data as PushBatchRow | null) ?? null
}

export async function upsertOpenBatch(params: {
  recipientUserId: string
  batchKind: PushBatchKind
  batchKey: string
  windowEndsAt: Date
  meta: Record<string, unknown>
}): Promise<{
  row: PushBatchRow | null
  created: boolean
  /** Expired row still present — caller must flush (then retry upsert). */
  expiredRow?: PushBatchRow
}> {
  const existing = await getOpenBatch(
    params.recipientUserId,
    params.batchKind,
    params.batchKey
  )

  if (existing) {
    const endsAt = new Date(existing.window_ends_at).getTime()
    if (Date.now() < endsAt) {
      const { data, error } = await supabaseServiceRole
        .from("push_batch_windows")
        .update({
          meta: params.meta,
          updated_at: new Date().toISOString(),
        })
        .eq("recipient_user_id", params.recipientUserId)
        .eq("batch_kind", params.batchKind)
        .eq("batch_key", params.batchKey)
        .select("*")
        .maybeSingle()

      if (error) {
        console.error("[push-batch] update failed", error)
        return { row: existing, created: false }
      }
      return { row: (data as PushBatchRow) ?? existing, created: false }
    }

    // Expired — do NOT delete here. Deleting without flush drops undelivered pushes.
    return { row: null, created: false, expiredRow: existing }
  }

  const { data, error } = await supabaseServiceRole
    .from("push_batch_windows")
    .insert({
      recipient_user_id: params.recipientUserId,
      batch_kind: params.batchKind,
      batch_key: params.batchKey,
      window_ends_at: params.windowEndsAt.toISOString(),
      meta: params.meta,
    })
    .select("*")
    .maybeSingle()

  if (error) {
    // Concurrent insert race — re-read and treat as update.
    if (error.code === "23505") {
      const raced = await getOpenBatch(
        params.recipientUserId,
        params.batchKind,
        params.batchKey
      )
      if (raced) {
        const racedEnds = new Date(raced.window_ends_at).getTime()
        if (Date.now() >= racedEnds) {
          return { row: null, created: false, expiredRow: raced }
        }
        const { data: updated } = await supabaseServiceRole
          .from("push_batch_windows")
          .update({
            meta: params.meta,
            updated_at: new Date().toISOString(),
          })
          .eq("recipient_user_id", params.recipientUserId)
          .eq("batch_kind", params.batchKind)
          .eq("batch_key", params.batchKey)
          .select("*")
          .maybeSingle()
        return { row: (updated as PushBatchRow) ?? raced, created: false }
      }
    }
    console.error("[push-batch] insert failed", error)
    return { row: null, created: false }
  }

  return { row: data as PushBatchRow, created: true }
}

export async function deleteBatch(
  recipientUserId: string,
  batchKind: PushBatchKind,
  batchKey: string
): Promise<void> {
  const { error } = await supabaseServiceRole
    .from("push_batch_windows")
    .delete()
    .eq("recipient_user_id", recipientUserId)
    .eq("batch_kind", batchKind)
    .eq("batch_key", batchKey)

  if (error) {
    console.error("[push-batch] delete failed", error)
  }
}

export async function listDueBatches(limit = 50): Promise<PushBatchRow[]> {
  const { data, error } = await supabaseServiceRole
    .from("push_batch_windows")
    .select("*")
    .neq("batch_kind", "dm")
    .lte("window_ends_at", new Date().toISOString())
    .order("window_ends_at", { ascending: true })
    .limit(limit)

  if (error) {
    console.error("[push-batch] listDueBatches failed", error)
    return []
  }
  return (data as PushBatchRow[]) ?? []
}

/**
 * Atomically increment the per-conversation DM push count for one recipient.
 * Returns the updated meta (including `count`), or null on failure.
 */
export async function bumpDmPushBatch(params: {
  recipientUserId: string
  conversationId: string
  meta: Record<string, unknown>
  windowEndsAt: Date
}): Promise<{ count: number; meta: Record<string, unknown> } | null> {
  const { data, error } = await supabaseServiceRole.rpc("bump_dm_push_batch", {
    p_recipient_user_id: params.recipientUserId,
    p_conversation_id: params.conversationId,
    p_meta: params.meta,
    p_window_ends_at: params.windowEndsAt.toISOString(),
  })

  if (error) {
    console.error("[push-batch] bumpDmPushBatch failed", error)
    return null
  }

  const meta =
    data && typeof data === "object" && !Array.isArray(data)
      ? (data as Record<string, unknown>)
      : {}
  const raw = meta.count
  const count =
    typeof raw === "number"
      ? raw
      : typeof raw === "string"
        ? Number.parseInt(raw, 10)
        : 1
  return {
    count: Number.isFinite(count) && count > 0 ? count : 1,
    meta,
  }
}

export function formatBatchedPeopleLine(
  names: string[],
  verbPhrase: string
): { title: string; body: string } {
  const unique = [...new Set(names.map((n) => n.trim()).filter(Boolean))]
  const count = unique.length
  if (count <= 0) {
    return { title: verbPhrase, body: verbPhrase }
  }
  if (count === 1) {
    return {
      title: `${unique[0]} ${verbPhrase}`,
      body: `${unique[0]} ${verbPhrase}`,
    }
  }
  if (count === 2) {
    return {
      title: `2 people ${verbPhrase}`,
      body: `${unique[0]} and ${unique[1]} ${verbPhrase}`,
    }
  }
  if (count === 3) {
    return {
      title: `3 people ${verbPhrase}`,
      body: `${unique[0]}, ${unique[1]}, and ${unique[2]} ${verbPhrase}`,
    }
  }
  const others = count - 2
  return {
    title: `${count} people ${verbPhrase}`,
    body: `${unique[0]}, ${unique[1]} and ${others} others ${verbPhrase}`,
  }
}

export function formatBatchedFollowers(names: string[]): {
  title: string
  body: string
} {
  const unique = [...new Set(names.map((n) => n.trim()).filter(Boolean))]
  const count = unique.length
  if (count <= 0) {
    return { title: "New followers", body: "You have new followers." }
  }
  if (count === 1) {
    return {
      title: `${unique[0]} followed you`,
      body: `${unique[0]} followed you.`,
    }
  }
  if (count === 2) {
    return {
      title: "2 new followers",
      body: `${unique[0]} and ${unique[1]} followed you.`,
    }
  }
  if (count === 3) {
    return {
      title: "3 new followers",
      body: `${unique[0]}, ${unique[1]} and ${unique[2]} followed you.`,
    }
  }
  const others = count - 2
  return {
    title: `${count} new followers`,
    body: `${unique[0]}, ${unique[1]} and ${others} others followed you.`,
  }
}
