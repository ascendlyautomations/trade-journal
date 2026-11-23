import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import {
  BROADCAST_DURATION_LIMIT_COOLDOWN_MESSAGE,
  TRADE_ROOM_BROADCAST_COOLDOWN_MS,
} from "./tradeRoomBroadcastDurationLimit.ts"

function cooldownTable(admin: SupabaseClient<Database>) {
  return admin.from("room_live_broadcast_broadcaster_cooldowns")
}

export async function getBroadcasterCooldownUntil(
  admin: SupabaseClient<Database>,
  broadcasterUserId: string
): Promise<string | null> {
  const { data, error } = await cooldownTable(admin)
    .select("cooldown_until")
    .eq("broadcaster_user_id", broadcasterUserId)
    .maybeSingle()

  if (error) {
    console.error("[livekit/broadcast] cooldown lookup failed", error.message)
    return null
  }
  return data?.cooldown_until?.trim() || null
}

export async function assertBroadcasterMayStartVideoBroadcast(
  admin: SupabaseClient<Database>,
  broadcasterUserId: string,
  nowMs: number = Date.now()
): Promise<
  | { ok: true }
  | { ok: false; status: number; error: string; retryAfterSec: number }
> {
  const until = await getBroadcasterCooldownUntil(admin, broadcasterUserId)
  if (!until) return { ok: true }
  const untilMs = Date.parse(until)
  if (!Number.isFinite(untilMs) || untilMs <= nowMs) {
    return { ok: true }
  }
  const retryAfterSec = Math.max(1, Math.ceil((untilMs - nowMs) / 1000))
  return {
    ok: false,
    status: 429,
    error: BROADCAST_DURATION_LIMIT_COOLDOWN_MESSAGE,
    retryAfterSec,
  }
}

export async function setBroadcasterBroadcastCooldown(
  admin: SupabaseClient<Database>,
  broadcasterUserId: string,
  nowMs: number = Date.now()
): Promise<void> {
  const until = new Date(nowMs + TRADE_ROOM_BROADCAST_COOLDOWN_MS).toISOString()
  const { error } = await cooldownTable(admin).upsert(
    {
      broadcaster_user_id: broadcasterUserId,
      cooldown_until: until,
      updated_at: new Date(nowMs).toISOString(),
    },
    { onConflict: "broadcaster_user_id" }
  )
  if (error) {
    console.error("[livekit/broadcast] cooldown upsert failed", error.message)
  }
}