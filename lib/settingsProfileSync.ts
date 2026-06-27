import type { SupabaseClient } from "@supabase/supabase-js"
import type { UserProfileSlice } from "@/lib/UserProfileProvider"
import { normalizeTraderType } from "@/lib/traderType"
import { writeUserBootstrapProfile } from "@/lib/userBootstrapCache"
import {
  readSettingsProfileCache,
  writeSettingsProfileCache,
} from "@/lib/settingsProfileCache"

export const APP_PROFILE_SELECT =
  "id, name, username, bio, is_private, avatar_url, trading_style, trading_model, trader_type, primary_market, started_trading, username_change_count, referral_code, referral_count, is_pro, subscription_status, cancel_at_period_end, cancel_at, trial_end, current_period_end, stripe_customer_id, is_banned, banned_reason, is_beta_tester, onboarding_completed, has_seen_getting_started_intro, has_seen_onboarding_complete_popup, max_drawdown_limit, has_email_password" as const

/** @deprecated Use APP_PROFILE_SELECT — kept for imports that expect this name. */
export const SETTINGS_PROFILE_SELECT = APP_PROFILE_SELECT

const settingsProfileInFlight = new Map<
  string,
  Promise<Record<string, unknown> | null>
>()

export async function fetchSettingsProfileRow(
  client: SupabaseClient,
  userId: string,
  options?: { force?: boolean }
): Promise<Record<string, unknown> | null> {
  const key = userId.trim()
  if (!key) return null

  if (!options?.force) {
    const cached = readSettingsProfileCache(key)
    if (cached) return cached
  }

  const existing = settingsProfileInFlight.get(key)
  if (existing) return existing

  const promise = (async () => {
    const { data } = await client
      .from("profiles")
      .select(APP_PROFILE_SELECT)
      .eq("id", key)
      .single()

    if (data) {
      writeSettingsProfileCache(key, data)
      writeUserBootstrapProfile(key, data)
    }

    return data ?? null
  })().finally(() => {
    settingsProfileInFlight.delete(key)
  })

  settingsProfileInFlight.set(key, promise)
  return promise
}

export function sliceDateInput(raw: unknown): string {
  if (raw == null || raw === "") return ""
  const s = String(raw)
  if (/^\d{4}-\d{2}-\d{2}/.test(s)) return s.slice(0, 10)
  const d = new Date(s)
  if (Number.isNaN(d.getTime())) return ""
  return d.toISOString().slice(0, 10)
}

export type SettingsFormSeed = {
  name: string
  username: string
  bio: string
  isPrivate: boolean
  avatarPreview: string | null
  tradingStyle: string
  traderType: string
  primaryMarket: string
  tradingModel: string
  startedTrading: string
}

export function buildSettingsFormSeed(
  row: Record<string, unknown> | null | undefined
): SettingsFormSeed | null {
  if (!row) return null

  return {
    name: (row.name as string) || "",
    username: (row.username as string) || "",
    bio: (row.bio as string) || "",
    isPrivate: Boolean(row.is_private),
    avatarPreview: (row.avatar_url as string) || null,
    tradingStyle:
      (row.trading_style as string) || (row.trading_model as string) || "",
    traderType: normalizeTraderType(row.trader_type),
    primaryMarket: (row.primary_market as string) || "",
    tradingModel: (row.trading_model as string) || "",
    startedTrading: sliceDateInput(row.started_trading),
  }
}

/** Merge shared bootstrap slice into a settings profile row (settings fields win). */
export function mergeSettingsProfileSources(
  settingsRow: Record<string, unknown> | null | undefined,
  shared: UserProfileSlice | null | undefined
): Record<string, unknown> | null {
  if (!settingsRow && !shared) return null
  if (!shared) return settingsRow ?? null
  if (!settingsRow) {
    return { ...shared } as Record<string, unknown>
  }
  return {
    ...shared,
    ...settingsRow,
    id: settingsRow.id ?? shared.id,
  }
}

export function sharedSliceToSettingsRow(
  shared: UserProfileSlice
): Record<string, unknown> {
  return { ...shared }
}

export function persistSettingsProfileEverywhere(
  userId: string,
  profile: Record<string, unknown>
) {
  writeSettingsProfileCache(userId, profile)
  writeUserBootstrapProfile(userId, profile)
}

export function settingsSaveToSharedSlice(
  profile: Record<string, unknown> | null,
  shared: UserProfileSlice | null
): UserProfileSlice | null {
  if (!shared) return null
  return {
    ...shared,
    username:
      profile?.username != null ? String(profile.username) : shared.username,
    avatar_url:
      profile?.avatar_url != null
        ? String(profile.avatar_url)
        : shared.avatar_url,
    bio: profile?.bio != null ? String(profile.bio) : shared.bio,
    is_private:
      typeof profile?.is_private === "boolean"
        ? profile.is_private
        : shared.is_private,
    trading_style:
      profile?.trading_style != null
        ? String(profile.trading_style)
        : shared.trading_style,
    trader_type:
      profile?.trader_type != null
        ? (profile.trader_type as string | null)
        : shared.trader_type,
    primary_market:
      profile?.primary_market != null
        ? String(profile.primary_market)
        : shared.primary_market,
    started_trading:
      profile?.started_trading != null
        ? String(profile.started_trading)
        : shared.started_trading,
    is_pro:
      typeof profile?.is_pro === "boolean" ? profile.is_pro : shared.is_pro,
    subscription_status:
      profile?.subscription_status != null
        ? String(profile.subscription_status)
        : shared.subscription_status,
    has_email_password:
      typeof profile?.has_email_password === "boolean"
        ? profile.has_email_password
        : shared.has_email_password,
  }
}
