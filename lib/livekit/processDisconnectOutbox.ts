import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import { isLiveKitConfigured } from "./config.ts"
import { disconnectUserFromTradeRoomLiveKit } from "./liveKitRoomService.ts"
import { shouldDisconnectLiveKitMember } from "./shouldDisconnectLiveKitMember.ts"

type OutboxRow = {
  id: string
  room_id: string
  user_id: string
  reason: string
  attempt_count: number | null
}

const BATCH_SIZE = 40

export type ProcessOutboxResult = {
  processed: number
  failed: number
  skipped: number
  skippedLiveKit: boolean
}

async function claimOutboxRows(
  admin: SupabaseClient<Database>,
  limit: number,
  outboxId?: string
): Promise<OutboxRow[]> {
  const { data, error } = await admin.rpc("room_livekit_claim_outbox", {
    p_limit: outboxId ? 1 : limit,
    p_outbox_id: outboxId ?? undefined,
  })

  if (error) {
    console.error("[livekit/outbox] claim failed", error.message)
    throw error
  }

  return (data ?? []) as OutboxRow[]
}

async function finalizeOutboxRow(
  admin: SupabaseClient<Database>,
  id: string,
  options: {
    processed: boolean
    lastError: string | null
    clearClaim?: boolean
  }
): Promise<void> {
  type OutboxUpdate =
    Database["public"]["Tables"]["room_livekit_disconnect_outbox"]["Update"]

  const patch: OutboxUpdate = {
    last_error: options.lastError,
  }
  if (options.processed) {
    patch.processed_at = new Date().toISOString()
    patch.processing_claimed_at = null
  } else if (options.clearClaim !== false) {
    patch.processing_claimed_at = null
  }

  await admin.from("room_livekit_disconnect_outbox").update(patch).eq("id", id)
}

async function processRow(
  admin: SupabaseClient<Database>,
  row: OutboxRow
): Promise<"processed" | "failed" | "skipped"> {
  try {
    const stillRevoked = await shouldDisconnectLiveKitMember(
      admin,
      row.room_id,
      row.user_id
    )

    if (!stillRevoked) {
      await finalizeOutboxRow(admin, row.id, {
        processed: true,
        lastError: "skipped:user_reinstated",
      })
      return "skipped"
    }

    const result = await disconnectUserFromTradeRoomLiveKit(
      admin,
      row.room_id,
      row.user_id
    )

    const combinedError =
      result.errors.length > 0 ? result.errors.join("; ").slice(0, 500) : null

    if (combinedError && result.removed === 0 && result.attempted > 0) {
      await finalizeOutboxRow(admin, row.id, {
        processed: false,
        lastError: combinedError,
        clearClaim: true,
      })
      return "failed"
    }

    await finalizeOutboxRow(admin, row.id, {
      processed: true,
      lastError: combinedError,
    })
    return "processed"
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    await finalizeOutboxRow(admin, row.id, {
      processed: false,
      lastError: message.slice(0, 500),
      clearClaim: true,
    })
    return "failed"
  }
}

export async function processLiveKitDisconnectOutbox(
  admin: SupabaseClient<Database>,
  options?: { outboxId?: string; limit?: number }
): Promise<ProcessOutboxResult> {
  if (!isLiveKitConfigured()) {
    return {
      processed: 0,
      failed: 0,
      skipped: 0,
      skippedLiveKit: true,
    }
  }

  const limit = options?.limit ?? BATCH_SIZE
  const rows = await claimOutboxRows(admin, limit, options?.outboxId)

  let processed = 0
  let failed = 0
  let skipped = 0

  for (const row of rows) {
    const outcome = await processRow(admin, row)
    if (outcome === "processed") processed += 1
    else if (outcome === "failed") failed += 1
    else skipped += 1
  }

  return { processed, failed, skipped, skippedLiveKit: false }
}
