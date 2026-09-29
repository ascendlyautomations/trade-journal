import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types.ts"
import {
  isPlatformUpdateCategoryId,
  isPlatformUpdateDestinationId,
  platformUpdateDestinationHref,
  type PlatformUpdateCategoryId,
  type PlatformUpdateDestinationId,
} from "@/lib/platformUpdateDestinations"
import { deliverPlatformUpdateBroadcastNow } from "@/lib/server/platformUpdates/broadcastWorker"

export type PlatformUpdateRecord = {
  id: string
  title: string
  body: string
  category: PlatformUpdateCategoryId
  destination: PlatformUpdateDestinationId
  send_push: boolean
  status: "draft" | "scheduled" | "published" | "cancelled"
  publish_at: string | null
  published_at: string | null
  created_by: string | null
  created_at: string
  updated_at: string
}

export type PlatformUpdateBroadcastRecord = {
  id: string
  update_id: string
  status: string
  attempted_count: number
  success_count: number
  failed_count: number
  started_at: string | null
  completed_at: string | null
  created_at: string
}

export function serializeAdminPlatformUpdate(
  row: PlatformUpdateRecord,
  broadcast: PlatformUpdateBroadcastRecord | null
) {
  return {
    id: row.id,
    title: row.title,
    body: row.body,
    category: row.category,
    destination: row.destination,
    destinationHref: platformUpdateDestinationHref(row.destination),
    sendPush: row.send_push,
    status: row.status,
    publishAt: row.publish_at,
    publishedAt: row.published_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    broadcast: broadcast
      ? {
          id: broadcast.id,
          status: broadcast.status,
          attemptedCount: broadcast.attempted_count,
          successCount: broadcast.success_count,
          failedCount: broadcast.failed_count,
          startedAt: broadcast.started_at,
          completedAt: broadcast.completed_at,
        }
      : null,
  }
}

export function validatePlatformUpdateInput(input: {
  title?: string
  body?: string
  category?: string
  destination?: string
  send_push?: boolean
  publish_at?: string | null
  status?: string
}): string | null {
  const title = input.title?.trim() ?? ""
  const body = input.body?.trim() ?? ""
  if (title.length < 1 || title.length > 200) {
    return "Title must be between 1 and 200 characters."
  }
  if (body.length < 1 || body.length > 8000) {
    return "Body must be between 1 and 8000 characters."
  }
  if (input.category && !isPlatformUpdateCategoryId(input.category)) {
    return "Invalid category."
  }
  if (input.destination && !isPlatformUpdateDestinationId(input.destination)) {
    return "Invalid destination."
  }
  if (input.status === "scheduled") {
    if (!input.publish_at?.trim()) {
      return "Scheduled updates require publish_at."
    }
    const at = new Date(input.publish_at)
    if (Number.isNaN(at.getTime())) return "Invalid publish_at."
    if (at.getTime() <= Date.now()) {
      return "Scheduled time must be in the future."
    }
  }
  return null
}

export async function listPublishedPlatformUpdates(
  supabase: SupabaseClient<Database>
): Promise<PlatformUpdateRecord[]> {
  const { data, error } = await supabase
    .from("platform_updates")
    .select("*")
    .eq("status", "published")
    .order("published_at", { ascending: false })

  if (error) throw new Error(error.message)
  return (data ?? []) as PlatformUpdateRecord[]
}

export async function listAdminPlatformUpdates(
  supabase: SupabaseClient<Database>
): Promise<
  (PlatformUpdateRecord & { broadcast: PlatformUpdateBroadcastRecord | null })[]
> {
  const { data: updates, error } = await supabase
    .from("platform_updates")
    .select("*")
    .order("updated_at", { ascending: false })

  if (error) throw new Error(error.message)

  const { data: broadcasts } = await supabase
    .from("platform_update_broadcasts")
    .select("*")

  const byUpdate = new Map<string, PlatformUpdateBroadcastRecord>()
  for (const row of broadcasts ?? []) {
    byUpdate.set(String((row as PlatformUpdateBroadcastRecord).update_id), row as PlatformUpdateBroadcastRecord)
  }

  return (updates ?? []).map((update) => ({
    ...(update as PlatformUpdateRecord),
    broadcast: byUpdate.get(String(update.id)) ?? null,
  }))
}

export async function getPlatformUpdateBroadcast(
  supabase: SupabaseClient<Database>,
  updateId: string
): Promise<PlatformUpdateBroadcastRecord | null> {
  const { data } = await supabase
    .from("platform_update_broadcasts")
    .select("*")
    .eq("update_id", updateId)
    .maybeSingle()
  return (data as PlatformUpdateBroadcastRecord | null) ?? null
}

export async function publishPlatformUpdateNow(params: {
  supabase: SupabaseClient<Database>
  updateId: string
  adminUserId: string
}): Promise<
  | { ok: true; update: PlatformUpdateRecord; broadcastId: string | null }
  | { ok: false; reason: string }
> {
  const nowIso = new Date().toISOString()

  const { data: update, error } = await params.supabase
    .from("platform_updates")
    .update({
      status: "published",
      published_at: nowIso,
      publish_at: nowIso,
      updated_at: nowIso,
    })
    .eq("id", params.updateId)
    .in("status", ["draft", "scheduled"])
    .select("*")
    .maybeSingle()

  if (error) {
    return { ok: false, reason: error.message }
  }
  if (!update) {
    return { ok: false, reason: "Update not found or already published." }
  }

  const row = update as PlatformUpdateRecord
  let broadcastId: string | null = null

  if (row.send_push) {
    const { data: broadcast, error: bErr } = await params.supabase
      .from("platform_update_broadcasts")
      .insert({ update_id: row.id, status: "pending" })
      .select("id")
      .maybeSingle()

    if (bErr?.code === "23505") {
      const existing = await getPlatformUpdateBroadcast(params.supabase, row.id)
      broadcastId = existing?.id ?? null
    } else if (bErr) {
      console.error("[platform-updates] broadcast insert failed", bErr)
    } else {
      broadcastId = broadcast?.id ?? null
    }
  }

  return { ok: true, update: row, broadcastId }
}

export async function publishDueScheduledPlatformUpdates(
  supabase: SupabaseClient<Database>
): Promise<{ published: number }> {
  const nowIso = new Date().toISOString()
  const { data: due, error } = await supabase
    .from("platform_updates")
    .select("id, created_by")
    .eq("status", "scheduled")
    .lte("publish_at", nowIso)
    .order("publish_at", { ascending: true })
    .limit(10)

  if (error) {
    console.error("[platform-updates] due query failed", error)
    return { published: 0 }
  }

  let published = 0
  for (const row of due ?? []) {
    const result = await publishPlatformUpdateNow({
      supabase,
      updateId: String(row.id),
      adminUserId: String(row.created_by ?? ""),
    })
    if (result.ok) {
      published += 1
      if (result.broadcastId) {
        await deliverPlatformUpdateBroadcastNow(result.broadcastId)
      }
    }
  }
  return { published }
}
