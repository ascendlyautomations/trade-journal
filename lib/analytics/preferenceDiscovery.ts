import type { SupabaseClient } from "@supabase/supabase-js"
import { isAccountEligibleForAutoTour, parseAccountCreatedAt } from "@/lib/contextualTour/eligibility"

export type PreferenceDiscoveryResponse = "completed" | "skipped" | "dismissed"

export type PreferenceDiscoveryPlacement = "firstTrade" | "quiet"

const responseRank: Record<PreferenceDiscoveryResponse, number> = {
  skipped: 1,
  dismissed: 2,
  completed: 3,
}

export function isPreferenceDiscoveryResponse(
  value: unknown
): value is PreferenceDiscoveryResponse {
  return value === "completed" || value === "skipped" || value === "dismissed"
}

/**
 * Where the invitation may appear.
 * A saved preferences row is configured even when every optional field is blank.
 * New accounts wait until the walkthrough is finished and a trade has been saved.
 */
export function preferenceDiscoveryPlacement(input: {
  configured: boolean
  response: PreferenceDiscoveryResponse | null
  tourEligible: boolean
  tourSettled: boolean
  tourBlocking: boolean
  hasTrade: boolean
}): PreferenceDiscoveryPlacement | null {
  if (input.configured || input.response === "completed" || input.response === "dismissed") {
    return null
  }
  if (input.tourBlocking) return null

  const firstTradeReady =
    input.tourEligible &&
    input.tourSettled &&
    input.hasTrade &&
    input.response == null

  if (firstTradeReady) return "firstTrade"
  if (input.tourEligible && input.response == null) return null
  if (input.response === "skipped" || !input.tourEligible) return "quiet"
  return null
}

export function preferenceTourEligible(createdAt: string | null | undefined): boolean {
  return isAccountEligibleForAutoTour(parseAccountCreatedAt(createdAt))
}

type Client = SupabaseClient

export async function fetchTradingPreferenceDiscovery(
  client: Client,
  userId: string
): Promise<PreferenceDiscoveryResponse | null> {
  const { data, error } = await client
    .from("trading_preference_discovery")
    .select("response")
    .eq("user_id", userId)
    .maybeSingle()
  if (error) throw error
  const response = data?.response
  return isPreferenceDiscoveryResponse(response) ? response : null
}

export async function fetchTradingPreferencesConfigured(
  client: Client,
  userId: string
): Promise<boolean> {
  const { data, error } = await client
    .from("trading_preferences")
    .select("user_id")
    .eq("user_id", userId)
    .maybeSingle()
  if (error) throw error
  return data != null
}

export async function fetchHasJournalTrade(
  client: Client,
  userId: string
): Promise<boolean> {
  const { data, error } = await client
    .from("trades")
    .select("id")
    .eq("user_id", userId)
    .neq("mode", "backtest")
    .limit(1)
  if (error) throw error
  return (data ?? []).length > 0
}

export async function recordTradingPreferenceDiscovery(
  client: Client,
  userId: string,
  response: PreferenceDiscoveryResponse
): Promise<PreferenceDiscoveryResponse> {
  const current = await fetchTradingPreferenceDiscovery(client, userId)
  if (current && responseRank[current] >= responseRank[response]) return current
  const { error } = await client.from("trading_preference_discovery").upsert(
    { user_id: userId, response } as never,
    { onConflict: "user_id" }
  )
  if (error) throw error
  return response
}
