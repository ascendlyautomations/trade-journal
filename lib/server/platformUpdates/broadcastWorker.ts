import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import {
  platformUpdateDestinationHref,
  type PlatformUpdateDestinationId,
} from "@/lib/platformUpdateDestinations"
import {
  getApnsRuntimeInfo,
  isApnsConfigured,
  sendApnsAlert,
} from "@/lib/server/push/apns"
import { removeInvalidDevicePushToken } from "@/lib/server/push/pushDispatcher"
import { redactDeviceToken } from "@/lib/server/push/deviceTokenRedaction"

const BATCH_SIZE = 80
const MAX_BATCHES_PER_INVOCATION = 8
const TERMINAL_BROADCAST_STATUSES = new Set([
  "sent",
  "partial_failure",
  "failed",
])

export type BroadcastProcessResult = {
  processedBroadcasts: number
  tokensAttempted: number
}

export type PlatformUpdateBroadcastDeliveryResult = {
  broadcastId: string
  status: string
  attemptedCount: number
  successCount: number
  failedCount: number
  apnsConfigured: boolean
  apnsProduction: boolean
  apnsBundleId: string
  iosTokenRows: number
  incomplete: boolean
  lastApnsFailureReason: string | null
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
  send_push: boolean
}

async function countIosPushTokenRows(): Promise<number> {
  const { count, error } = await supabaseServiceRole
    .from("device_push_tokens")
    .select("id", { count: "exact", head: true })
    .eq("platform", "ios")

  if (error) {
    console.error("[platform-update-broadcast] ios token count failed", error)
    return 0
  }
  return count ?? 0
}

async function loadBroadcast(broadcastId: string): Promise<BroadcastRow | null> {
  const { data, error } = await supabaseServiceRole
    .from("platform_update_broadcasts")
    .select(
      "id,update_id,status,attempted_count,success_count,failed_count,cursor_token_id,started_at"
    )
    .eq("id", broadcastId)
    .maybeSingle()

  if (error || !data) return null
  return data as BroadcastRow
}

async function loadUpdate(updateId: string): Promise<UpdateRow | null> {
  const { data, error } = await supabaseServiceRole
    .from("platform_updates")
    .select("title,body,destination,send_push")
    .eq("id", updateId)
    .eq("status", "published")
    .maybeSingle()

  if (error || !data) return null
  return data as UpdateRow
}

function isDeliverableIosToken(row: {
  id?: string | null
  device_token?: string | null
}): boolean {
  const token = String(row.device_token ?? "").trim()
  return Boolean(row.id && token)
}

async function processOneBroadcast(broadcast: BroadcastRow): Promise<{
  tokensThisRun: number
  lastApnsFailureReason: string | null
}> {
  const update = await loadUpdate(broadcast.update_id)
  if (!update) {
    console.error("[platform-update-broadcast] published update missing", {
      broadcastId: broadcast.id,
      updateId: broadcast.update_id,
    })
    await supabaseServiceRole
      .from("platform_update_broadcasts")
      .update({
        status: "failed",
        completed_at: new Date().toISOString(),
      })
      .eq("id", broadcast.id)
    return { tokensThisRun: 0, lastApnsFailureReason: "update_not_published" }
  }

  if (!update.send_push) {
    console.warn("[platform-update-broadcast] send_push false — skipping APNs", {
      broadcastId: broadcast.id,
      updateId: broadcast.update_id,
    })
    await supabaseServiceRole
      .from("platform_update_broadcasts")
      .update({
        status: "failed",
        completed_at: new Date().toISOString(),
      })
      .eq("id", broadcast.id)
    return { tokensThisRun: 0, lastApnsFailureReason: "send_push_disabled" }
  }

  const apnsInfo = getApnsRuntimeInfo()
  if (!isApnsConfigured()) {
    console.error("[platform-update-broadcast] APNs not configured", {
      broadcastId: broadcast.id,
      apns: apnsInfo,
    })
    await supabaseServiceRole
      .from("platform_update_broadcasts")
      .update({
        status: "failed",
        completed_at: new Date().toISOString(),
      })
      .eq("id", broadcast.id)
    return { tokensThisRun: 0, lastApnsFailureReason: "apns_not_configured" }
  }

  console.info("[platform-update-broadcast] starting batch run", {
    broadcastId: broadcast.id,
    updateId: broadcast.update_id,
    apnsProduction: apnsInfo.production,
    apnsBundleId: apnsInfo.bundleId,
    broadcastStatus: broadcast.status,
    attemptedSoFar: broadcast.attempted_count,
  })

  const href = platformUpdateDestinationHref(update.destination)
  let cursor = broadcast.cursor_token_id
  let attempted = broadcast.attempted_count
  let success = broadcast.success_count
  let failed = broadcast.failed_count
  let tokensThisRun = 0
  let lastApnsFailureReason: string | null = null

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
      console.error("[platform-update-broadcast] token page failed", {
        broadcastId: broadcast.id,
        error,
      })
      break
    }

    const tokens = (rows ?? []).filter(isDeliverableIosToken)

    console.info("[platform-update-broadcast] token page", {
      broadcastId: broadcast.id,
      rawRows: rows?.length ?? 0,
      deliverable: tokens.length,
      cursor,
    })

    if (!tokens.length) {
      const finalStatus =
        attempted === 0
          ? "failed"
          : failed > 0 && success > 0
            ? "partial_failure"
            : failed > 0 && success === 0
              ? "failed"
              : "sent"

      if (attempted === 0) {
        lastApnsFailureReason = "no_ios_device_tokens"
        console.error("[platform-update-broadcast] no iOS tokens to deliver", {
          broadcastId: broadcast.id,
        })
      }

      console.info("[platform-update-broadcast] complete", {
        broadcastId: broadcast.id,
        updateId: broadcast.update_id,
        status: finalStatus,
        attempted,
        success,
        failed,
        lastApnsFailureReason,
      })

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
      return { tokensThisRun, lastApnsFailureReason }
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
        console.info("[platform-update-broadcast] apns success", {
          broadcastId: broadcast.id,
          updateId: broadcast.update_id,
          tokenPrefix: redactDeviceToken(deviceToken),
        })
      } else {
        failed += 1
        lastApnsFailureReason = result.reason
        console.error("[platform-update-broadcast] apns failure", {
          broadcastId: broadcast.id,
          updateId: broadcast.update_id,
          tokenPrefix: redactDeviceToken(deviceToken),
          httpStatus: result.status,
          reason: result.reason,
          invalidToken: result.invalidToken,
        })
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

  console.info("[platform-update-broadcast] batch run paused (more tokens)", {
    broadcastId: broadcast.id,
    attempted,
    success,
    failed,
  })

  return { tokensThisRun, lastApnsFailureReason }
}

export async function processPlatformUpdateBroadcasts(params?: {
  broadcastId?: string
}): Promise<BroadcastProcessResult> {
  let query = supabaseServiceRole
    .from("platform_update_broadcasts")
    .select(
      "id,update_id,status,attempted_count,success_count,failed_count,cursor_token_id,started_at"
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
    const run = await processOneBroadcast(row as BroadcastRow)
    tokensAttempted += run.tokensThisRun
  }

  return {
    processedBroadcasts: data?.length ?? 0,
    tokensAttempted,
  }
}

/** Runs batched delivery until terminal status or max rounds (Publish & Send — no cron). */
export async function deliverPlatformUpdateBroadcastNow(
  broadcastId: string
): Promise<PlatformUpdateBroadcastDeliveryResult> {
  const iosTokenRows = await countIosPushTokenRows()
  const apnsInfo = getApnsRuntimeInfo()
  let lastApnsFailureReason: string | null = null

  console.info("[platform-update-broadcast] immediate delivery requested", {
    broadcastId,
    iosTokenRows,
    apnsConfigured: apnsInfo.configured,
    apnsProduction: apnsInfo.production,
    apnsBundleId: apnsInfo.bundleId,
  })

  const maxRounds = 200
  for (let round = 0; round < maxRounds; round += 1) {
    const row = await loadBroadcast(broadcastId)
    if (!row) {
      lastApnsFailureReason = "broadcast_not_found"
      break
    }
    if (TERMINAL_BROADCAST_STATUSES.has(row.status)) {
      break
    }
    await processPlatformUpdateBroadcasts({ broadcastId })
  }

  const finalRow = await loadBroadcast(broadcastId)
  const status = finalRow?.status ?? "failed"
  const attemptedCount = finalRow?.attempted_count ?? 0
  const successCount = finalRow?.success_count ?? 0
  const failedCount = finalRow?.failed_count ?? 0
  const incomplete = status === "sending"

  if (successCount === 0 && failedCount > 0 && !lastApnsFailureReason) {
    lastApnsFailureReason = "all_apns_failed"
  }
  if (attemptedCount === 0 && status === "failed" && !lastApnsFailureReason) {
    lastApnsFailureReason = iosTokenRows === 0 ? "no_ios_device_tokens" : "delivery_failed"
  }

  console.info("[platform-update-broadcast] immediate delivery finished", {
    broadcastId,
    status,
    iosTokenRows,
    attempted: attemptedCount,
    success: successCount,
    failed: failedCount,
    incomplete,
    lastApnsFailureReason,
  })

  return {
    broadcastId,
    status,
    attemptedCount,
    successCount,
    failedCount,
    apnsConfigured: apnsInfo.configured,
    apnsProduction: apnsInfo.production,
    apnsBundleId: apnsInfo.bundleId,
    iosTokenRows,
    incomplete,
    lastApnsFailureReason,
  }
}
