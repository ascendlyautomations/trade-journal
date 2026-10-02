import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "../database.types.ts"
import {
  LAUNCH_ACCESS_DISABLED,
  MONETIZATION_FLAGS_FAIL_CLOSED,
  parseLaunchAccessMode,
  resolveEffectiveMonetizationFlags,
  type EffectiveMonetizationFlags,
  type LaunchAccessMode,
  type MonetizationAccountOverride,
  type MonetizationGlobalSettings,
} from "../monetizationConfig.ts"

type SettingsRow = {
  ios_paywall_enabled: boolean
  web_paywall_enabled: boolean
  entitlement_enforcement_enabled: boolean
  launch_access_mode: string
  launch_access_cutoff_at: string | null
}

type OverrideRow = {
  ios_paywall_enabled: boolean | null
  web_paywall_enabled: boolean | null
  entitlement_enforcement_enabled: boolean | null
}

function mapSettings(row: SettingsRow | null): MonetizationGlobalSettings | null {
  if (!row) return null
  return {
    iosPaywallEnabled: row.ios_paywall_enabled === true,
    webPaywallEnabled: row.web_paywall_enabled === true,
    entitlementEnforcementEnabled: row.entitlement_enforcement_enabled === true,
    launchAccessMode: parseLaunchAccessMode(row.launch_access_mode),
    launchAccessCutoffAt: row.launch_access_cutoff_at,
  }
}

function databaseClient(supabase: SupabaseClient): SupabaseClient<Database> {
  return supabase as SupabaseClient<Database>
}

export async function loadMonetizationGlobalSettings(
  supabase: SupabaseClient
): Promise<MonetizationGlobalSettings | null> {
  const client = databaseClient(supabase)
  const { data, error } = await client
    .from("app_monetization_settings")
    .select(
      "ios_paywall_enabled,web_paywall_enabled,entitlement_enforcement_enabled,launch_access_mode,launch_access_cutoff_at"
    )
    .eq("id", 1)
    .maybeSingle<SettingsRow>()

  if (error || !data) return null
  return mapSettings(data)
}

export async function loadMonetizationAccountOverride(
  supabase: SupabaseClient,
  userId: string
): Promise<MonetizationAccountOverride | null> {
  const { data, error } = await databaseClient(supabase)
    .from("app_monetization_account_overrides")
    .select("ios_paywall_enabled,web_paywall_enabled,entitlement_enforcement_enabled")
    .eq("user_id", userId)
    .maybeSingle<OverrideRow>()

  if (error || !data) return null
  return {
    iosPaywallEnabled: data.ios_paywall_enabled,
    webPaywallEnabled: data.web_paywall_enabled,
    entitlementEnforcementEnabled: data.entitlement_enforcement_enabled,
  }
}

export type MonetizationConfigSnapshot = {
  flags: EffectiveMonetizationFlags
  /** False when the global settings row could not be read. Overrides are not applied in that case. */
  settingsPresent: boolean
  globalIosPaywallEnabled: boolean
  /** Null means this account has no paywall override and inherits the global flag. */
  accountIosPaywallOverride: boolean | null
}

export async function loadMonetizationConfigSnapshot(
  supabase: SupabaseClient,
  userId: string
): Promise<MonetizationConfigSnapshot> {
  try {
    const [globalSettings, accountOverride] = await Promise.all([
      loadMonetizationGlobalSettings(supabase),
      loadMonetizationAccountOverride(supabase, userId),
    ])
    return {
      flags: resolveEffectiveMonetizationFlags(globalSettings, accountOverride),
      settingsPresent: globalSettings != null,
      globalIosPaywallEnabled: globalSettings?.iosPaywallEnabled === true,
      accountIosPaywallOverride: accountOverride?.iosPaywallEnabled ?? null,
    }
  } catch {
    return {
      flags: { ...MONETIZATION_FLAGS_FAIL_CLOSED },
      settingsPresent: false,
      globalIosPaywallEnabled: false,
      accountIosPaywallOverride: null,
    }
  }
}

export async function loadEffectiveMonetizationFlags(
  supabase: SupabaseClient,
  userId: string
): Promise<EffectiveMonetizationFlags> {
  return (await loadMonetizationConfigSnapshot(supabase, userId)).flags
}

/** Global Free-plan limit switch. Missing config stays off (do not newly restrict). */
export async function entitlementEnforcementEnabled(
  supabase: SupabaseClient
): Promise<boolean> {
  try {
    const settings = await loadMonetizationGlobalSettings(supabase)
    return settings?.entitlementEnforcementEnabled === true
  } catch {
    return false
  }
}

export async function loadLaunchAccessPolicy(
  supabase: SupabaseClient
): Promise<{
  launchAccessMode: LaunchAccessMode
  launchAccessCutoffAt: string | null
}> {
  try {
    const settings = await loadMonetizationGlobalSettings(supabase)
    if (!settings) return { ...LAUNCH_ACCESS_DISABLED }
    return {
      launchAccessMode: settings.launchAccessMode,
      launchAccessCutoffAt: settings.launchAccessCutoffAt,
    }
  } catch {
    return { ...LAUNCH_ACCESS_DISABLED }
  }
}
