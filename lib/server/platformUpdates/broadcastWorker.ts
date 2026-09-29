import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import {
  platformUpdateDestinationHref,
  type PlatformUpdateDestinationId,
} from "@/lib/platformUpdateDestinations"
import { isApnsConfigured, sendApnsAlert } from "@/lib/server/push/apns"
import { removeInvalidDevicePushToken } from "@/lib/server/push/pushDispatcher"

const BATCH_SIZE = 80
const MAX_BATCHES_PER_INVOCATION = 8

export type BroadcastProcessResult = {
  processedBroadcasts: number
  tokensAttempted: number
}

type BroadcastRow = {
  id: string
  update_id: string
  status: string
  attempted_count: number
  success_count: number
  failed_count: number
  cursor_token_id: string | null
  started_at?: string | null
}

type UpdateRow = {
  title: string
  body: string
  destination: PlatformUpdateDestinationId
}

async function loadUpdate(updateId: string): Promise<UpdateRow | null> {
  const { data, error } = await supabaseServiceRole
    .from("platform_updates")
    .select("title,body,destination")
    .eq("id", updateId)
    .eq("status", "published")
    .maybeSingle()

  if (error || !data) return null
  return data as UpdateRow
}

async function processOneBroadcast(broadcast: BroadcastRow): Promise<number> {
  const update = await loadUpdate(broadcast.update_id)
  if (!update) {
    await supabaseServiceRole
      .from("platform_update_broadcasts")
      .update({
        status: "failed",
        completed_at: new Date().toISOString(),
      })
      .eq("id", broadcast.id)
    return 0
  }

  if (!isApnsConfigured()) {
    await supabaseServiceRole
      .from("platform_update_broadcasts")
      .update({
        status: "failed",
        completed_at: new Date().toISOString(),
      })
      .eq("id", broadcast.id)
    return 0
  }

  const href = platformUpdateDestinationHref(update.destination)
  let cursor = broadcast.cursor_token_id
  let attempted = broadcast.attempted_count
  let success = broadcast.success_count
  let failed = broadcast.failed_count
  let tokensThisRun = 0

  if (broadcast.status === "pending") {
    await supabaseServiceRole
      .from("platform_update_broadcasts")
      .update({
        status: "sending",
        started_at: broadcast.started_at ?? new Date().toISOString(),
      })
      .eq("id", broadcast.id)
  }

  for (let batch = 0; batch < MAX_BATCHES_PER_INVOCATION; batch += 1) {
    let tokenQuery = supabaseServiceRole
      .from("device_push_tokens")
      .select("id, device_token")
      .eq("platform", "ios")
      .order("id", { ascending: true })
      .limit(BATCH_SIZE)

    if (cursor) {
      tokenQuery = tokenQuery.gt("id", cursor)
    }

    const { data: rows, error } = await tokenQuery
    if (error) {
      console.error("[platform-update-broadcast] token page failed", error)
      break
    }

    const tokens = (rows ?? []).filter(
      (r) => r.id && String(r.device_token ?? "").trim().length >= 16
    )

    if (!tokens.length) {
      const finalStatus =
        failed > 0 && success > 0
          ? "partial_failure"
          : failed > 0 && success === 0
            ? "failed"
            : "sent"
      await supabaseServiceRole
        .from("platform_update_broadcasts")
        .update({
          status: finalStatus,
          attempted_count: attempted,
          success_count: success,
          failed_count: failed,
          cursor_token_id: null,
          completed_at: new Date().toISOString(),
        })
        .eq("id", broadcast.id)
      return tokensThisRun
    }

    for (const row of tokens) {
      const tokenId = String(row.id)
      const deviceToken = String(row.device_token).trim()
      cursor = tokenId
      attempted += 1
      tokensThisRun += 1

      const result = await sendApnsAlert(deviceToken, {
        title: update.title,
        body: update.body,
        href,
        badge: 0,
        notificationType: "platform_update",
      })

      if (result.ok) {
        success += 1
      } else {
        failed += 1
        if (result.invalidToken) {
          await removeInvalidDevicePushToken(tokenId, deviceToken, result.reason)
        }
      }
    }

    await supabaseServiceRole
      .from("platform_update_broadcasts")
      .update({
        status: "sending",
        attempted_count: attempted,
        success_count: success,
        failed_count: failed,
        cursor_token_id: cursor,
      })
      .eq("id", broadcast.id)
  }

  return tokensThisRun
}

export async function processPlatformUpdateBroadcasts(params?: {
  broadcastId?: string
}): Promise<BroadcastProcessResult> {
  let query = supabaseServiceRole
    .from("platform_update_broadcasts")
    .select(
      "id,update_id,status,attempted_count,success_count,failed_count,cursor_token_id"
    )
    .in("status", ["pending", "sending"])
    .order("created_at", { ascending: true })
    .limit(params?.broadcastId ? 1 : 3)

  if (params?.broadcastId) {
    query = query.eq("id", params.broadcastId)
  }

  const { data, error } = await query
  if (error) {
    console.error("[platform-update-broadcast] load jobs failed", error)
    return { processedBroadcasts: 0, tokensAttempted: 0 }
  }

  let tokensAttempted = 0
  for (const row of data ?? []) {
    tokensAttempted += await processOneBroadcast(row as BroadcastRow)
  }

  return {
    processedBroadcasts: data?.length ?? 0,
    tokensAttempted,
  }
}
