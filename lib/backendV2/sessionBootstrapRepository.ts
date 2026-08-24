/**
 * Session bootstrap repositories (REST + RPC).
 * Existing production path remains default (flag OFF).
 */

import type { SupabaseClient } from "@supabase/supabase-js"
import { ACCOUNTS_SELECT } from "@/lib/appDataCache"
import { fetchTotalUnreadMessageCount } from "@/lib/messageUnread"
import { fetchSocialNotificationUnreadCount } from "@/lib/socialNotificationUnreadCount"
import { isProActive } from "@/lib/subscription"
import { APP_PROFILE_SELECT } from "@/lib/settingsProfileSync"
import type { SessionBootstrapProviding } from "./adapters.ts"
import {
  decodeSessionBootstrapV1,
  type SessionBootstrapV1,
  type SessionProfileV1,
} from "./contracts.ts"
import {
  BackendV2RpcClient,
  createSupabaseBackendV2Transport,
} from "./rpcClient.ts"
import { BackendV2RpcNames } from "./versioning.ts"
import { isBackendV2Enabled } from "./flags.ts"
import {
  clearSessionBootstrapCache,
  invalidateSessionBootstrap,
  readSessionBootstrapCache,
  writeSessionBootstrapCache,
} from "./sessionBootstrapCache.ts"
import {
  beginSessionBootstrapFlight,
  getSessionBootstrapFlight,
} from "./sessionBootstrapSingleFlight.ts"
import { ensureSupabaseSessionRpcSingleFlight } from "./ensureSupabaseSessionRpcSingleFlight.ts"
import {
  compareSessionBootstraps,
  logSessionBootstrapMismatches,
} from "./sessionBootstrapCompare.ts"
import {
  measureAsync,
  recordBackendV2Telemetry,
  utf8ByteLength,
} from "./telemetry.ts"

function asSessionProfile(row: Record<string, unknown>): SessionProfileV1 {
  return {
    id: String(row.id),
    username: row.username != null ? String(row.username) : null,
    avatar_url: row.avatar_url != null ? String(row.avatar_url) : null,
    is_pro: typeof row.is_pro === "boolean" ? row.is_pro : null,
    creator_access:
      typeof row.creator_access === "boolean" ? row.creator_access : null,
    subscription_status:
      row.subscription_status != null ? String(row.subscription_status) : null,
    trial_end: row.trial_end != null ? String(row.trial_end) : null,
    stripe_customer_id:
      row.stripe_customer_id != null ? String(row.stripe_customer_id) : null,
    signup_flow_source:
      row.signup_flow_source != null ? String(row.signup_flow_source) : null,
    early_access_enrolled_at:
      row.early_access_enrolled_at != null
        ? String(row.early_access_enrolled_at)
        : null,
    early_access_started_at:
      row.early_access_started_at != null
        ? String(row.early_access_started_at)
        : null,
    early_access_ends_at:
      row.early_access_ends_at != null
        ? String(row.early_access_ends_at)
        : null,
    early_access_status:
      row.early_access_status != null ? String(row.early_access_status) : null,
    early_access_campaign_id:
      row.early_access_campaign_id != null
        ? String(row.early_access_campaign_id)
        : null,
    early_access_enrollment_source:
      row.early_access_enrollment_source != null
        ? String(row.early_access_enrollment_source)
        : null,
    lifetime_access_source:
      row.lifetime_access_source != null
        ? String(row.lifetime_access_source)
        : null,
    lifetime_access_granted_at:
      row.lifetime_access_granted_at != null
        ? String(row.lifetime_access_granted_at)
        : null,
    is_banned: typeof row.is_banned === "boolean" ? row.is_banned : null,
    banned_reason:
      row.banned_reason != null ? String(row.banned_reason) : null,
    referral_code:
      row.referral_code != null ? String(row.referral_code) : null,
    is_beta_tester:
      typeof row.is_beta_tester === "boolean" ? row.is_beta_tester : null,
    use_free_tier:
      typeof row.use_free_tier === "boolean" ? row.use_free_tier : null,
    onboarding_completed:
      typeof row.onboarding_completed === "boolean"
        ? row.onboarding_completed
        : null,
    has_seen_getting_started_intro:
      typeof row.has_seen_getting_started_intro === "boolean"
        ? row.has_seen_getting_started_intro
        : null,
    has_seen_onboarding_complete_popup:
      typeof row.has_seen_onboarding_complete_popup === "boolean"
        ? row.has_seen_onboarding_complete_popup
        : null,
    bio: row.bio != null ? String(row.bio) : null,
    trading_style:
      row.trading_style != null ? String(row.trading_style) : null,
    trader_type: row.trader_type != null ? String(row.trader_type) : null,
    primary_market:
      row.primary_market != null ? String(row.primary_market) : null,
    started_trading:
      row.started_trading != null ? String(row.started_trading) : null,
    max_drawdown_limit:
      typeof row.max_drawdown_limit === "number"
        ? row.max_drawdown_limit
        : row.max_drawdown_limit != null
          ? Number(row.max_drawdown_limit)
          : null,
    is_private: typeof row.is_private === "boolean" ? row.is_private : null,
    has_email_password:
      typeof row.has_email_password === "boolean"
        ? row.has_email_password
        : null,
  }
}

export class SessionRestBootstrapRepository implements SessionBootstrapProviding {
  constructor(
    private readonly client: SupabaseClient,
    private readonly userId: string
  ) {}

  async loadSessionBootstrap(): Promise<SessionBootstrapV1> {
    const uid = this.userId

    const [
      profileRes,
      accountsRes,
      followingRes,
      notifCountRes,
      dmUnread,
      prefsRes,
      adminRes,
      affiliateRes,
    ] = await Promise.all([
      this.client.from("profiles").select(APP_PROFILE_SELECT).eq("id", uid).single(),
      this.client.from("accounts").select(ACCOUNTS_SELECT).eq("user_id", uid),
      this.client.from("followers").select("following_id").eq("follower_id", uid),
      fetchSocialNotificationUnreadCount(uid, this.client),
      fetchTotalUnreadMessageCount(uid, this.client),
      this.client
        .from("notification_preferences")
        .select(
          "notifications_enabled, likes_enabled, comments_enabled, direct_messages_enabled, followers_enabled"
        )
        .eq("user_id", uid)
        .maybeSingle(),
      this.client.from("admin_users").select("user_id").eq("user_id", uid).maybeSingle(),
      this.client
        .from("affiliates")
        .select("user_id, is_active")
        .eq("user_id", uid)
        .eq("is_active", true)
        .maybeSingle(),
    ])

    if (profileRes.error || !profileRes.data) {
      throw profileRes.error ?? new Error("SessionRest: profile missing")
    }

    const row = profileRes.data as Record<string, unknown>
    const sessionProfile = asSessionProfile(row)
    const pro = isProActive(sessionProfile)
    const early =
      sessionProfile.early_access_status === "active" &&
      sessionProfile.early_access_campaign_id === "traxs_pro_for_life_v1"

    const accounts = (accountsRes.data ?? []).map((a: Record<string, unknown>) => ({
      id: String(a.id),
      name: a.name != null ? String(a.name) : null,
      type: a.mode != null ? String(a.mode) : null,
      currency: null as string | null,
      is_active: a.is_active !== false,
    }))

    const following_ids = (followingRes.data ?? [])
      .map((r: { following_id?: string }) => String(r.following_id ?? ""))
      .filter(Boolean)

    const prefs = prefsRes.data as Record<string, unknown> | null

    return {
      meta: {
        contract_version: "v1",
        server_time: new Date().toISOString(),
        viewer_id: uid,
      },
      data: {
        viewer: {
          id: uid,
          username: sessionProfile.username,
          display_name: row.name != null ? String(row.name) : null,
          avatar_url: sessionProfile.avatar_url,
          is_private: Boolean(sessionProfile.is_private),
          onboarding_flags: {
            onboarding_completed: Boolean(sessionProfile.onboarding_completed),
            has_seen_getting_started_intro: Boolean(
              sessionProfile.has_seen_getting_started_intro
            ),
            has_seen_onboarding_complete_popup: Boolean(
              sessionProfile.has_seen_onboarding_complete_popup
            ),
          },
          entitlement: {
            plan: pro ? "pro" : "free",
            status: sessionProfile.subscription_status,
            flags: {
              is_pro: Boolean(sessionProfile.is_pro),
              creator_access: Boolean(sessionProfile.creator_access),
              early_access_active: Boolean(early),
              use_free_tier: Boolean(sessionProfile.use_free_tier),
              is_beta_tester: Boolean(sessionProfile.is_beta_tester),
              is_admin: Boolean(adminRes.data),
              is_affiliate: Boolean(affiliateRes.data),
            },
          },
        },
        session_profile: sessionProfile,
        accounts_summary: accounts,
        following_ids,
        badges: {
          notifications_unread: notifCountRes,
          dm_unread: dmUnread,
          rooms_unread: null,
        },
        prefs_min: {
          notifications_enabled_summary:
            prefs?.notifications_enabled !== false,
          messaging_defaults: {
            likes_enabled: prefs?.likes_enabled !== false,
            comments_enabled: prefs?.comments_enabled !== false,
            direct_messages_enabled: prefs?.direct_messages_enabled !== false,
            followers_enabled: prefs?.followers_enabled !== false,
          },
        },
        realtime: {
          channels: ["notifications", "messages", "profiles", "followers"],
        },
      },
    }
  }
}

export class SessionRpcBootstrapRepository implements SessionBootstrapProviding {
  private readonly client: BackendV2RpcClient

  constructor(supabase: SupabaseClient) {
    this.client = new BackendV2RpcClient({
      transport: createSupabaseBackendV2Transport(supabase),
    })
  }

  async loadSessionBootstrap(): Promise<SessionBootstrapV1> {
    return this.client.callKnown(
      BackendV2RpcNames.session,
      decodeSessionBootstrapV1,
      { flagName: "backendV2.session", cacheMiss: true }
    )
  }
}

export type SessionBootstrapLoadResult = {
  bootstrap: SessionBootstrapV1
  source: "rpc" | "rest" | "cache"
  dualRunMismatches: number
  restRequestEstimate: number
  rpcRequestCount: number
  durationMs: number
  payloadBytes: number
  cacheHit: boolean
}

function cacheHitResult(
  uid: string,
  cached: SessionBootstrapV1
): SessionBootstrapLoadResult {
  return {
    bootstrap: cached,
    source: "cache",
    dualRunMismatches: 0,
    restRequestEstimate: 0,
    rpcRequestCount: 0,
    durationMs: 0,
    payloadBytes: 0,
    cacheHit: true,
  }
}

/**
 * Flag OFF → never called from production shell (caller must gate).
 * Flag ON → RPC exactly once per authenticated user until invalidate/logout.
 * Concurrent callers share one Promise (globalThis single-flight).
 * Never re-runs bootstrap for Realtime — patch the cache instead.
 */
export async function loadSessionBootstrapForUser(
  client: SupabaseClient,
  userId: string,
  options?: { force?: boolean; authEvent?: string; caller?: string }
): Promise<SessionBootstrapLoadResult> {
  const uid = userId.trim()
  if (!uid) {
    throw new Error("loadSessionBootstrapForUser requires userId")
  }

  if (!isBackendV2Enabled("session")) {
    throw new Error(
      "loadSessionBootstrapForUser requires backendV2.session flag ON"
    )
  }

  ensureSupabaseSessionRpcSingleFlight(client)

  if (options?.force) {
    invalidateSessionBootstrap(uid)
  }

  if (!options?.force) {
    const cached = readSessionBootstrapCache(uid)
    if (cached) {
      return cacheHitResult(uid, cached)
    }

    const existing = getSessionBootstrapFlight<SessionBootstrapLoadResult>(uid)
    if (existing) {
      return existing
    }
  }

  return beginSessionBootstrapFlight(uid, async () => {
    // Re-check after winning the flight race (another caller may have finished).
    if (!options?.force) {
      const cached = readSessionBootstrapCache(uid)
      if (cached) {
        return cacheHitResult(uid, cached)
      }
    }

    const rpcRepo = new SessionRpcBootstrapRepository(client)
    const restRepo = new SessionRestBootstrapRepository(client, uid)

    const { value: rpc, ms } = await measureAsync(() =>
      rpcRepo.loadSessionBootstrap()
    )

    let dualRunMismatches = 0
    const dualRun =
      process.env.NODE_ENV === "development" &&
      (process.env.NEXT_PUBLIC_BACKEND_V2_DUAL_RUN === "1" ||
        process.env.NEXT_PUBLIC_BACKEND_V2_DUAL_RUN === "true")
    if (dualRun) {
      try {
        const rest = await restRepo.loadSessionBootstrap()
        const mismatches = compareSessionBootstraps(rest, rpc)
        dualRunMismatches = mismatches.length
        logSessionBootstrapMismatches(mismatches)
      } catch (err) {
        console.warn("[backendV2.session] dual-run REST failed", err)
        dualRunMismatches = -1
      }
    }

    writeSessionBootstrapCache(uid, rpc, "rpc")

    let payloadBytes = 0
    try {
      payloadBytes = utf8ByteLength(JSON.stringify(rpc))
    } catch {
      payloadBytes = 0
    }

    recordBackendV2Telemetry({
      rpcName: BackendV2RpcNames.session,
      success: true,
      executionMs: ms,
      decodeMs: null,
      payloadBytes,
      cacheHit: false,
      cacheMiss: true,
      errorCode: null,
      flagName: "backendV2.session",
    })

    return {
      bootstrap: rpc,
      source: "rpc",
      dualRunMismatches,
      restRequestEstimate: dualRun ? 8 : 0,
      rpcRequestCount: 1,
      durationMs: ms,
      payloadBytes,
      cacheHit: false,
    }
  })
}

export {
  clearSessionBootstrapCache,
  invalidateSessionBootstrap,
  readSessionBootstrapCache,
}
