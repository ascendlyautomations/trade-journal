import type { SupabaseClient } from "@supabase/supabase-js"
import type {
  ProfileInsightsBootstrapV1,
  ProfileInsightsQuery,
} from "./contract"

export async function fetchProfileInsightsBootstrap(
  client: SupabaseClient,
  query: ProfileInsightsQuery
): Promise<ProfileInsightsBootstrapV1> {
  const params =
    query.kind === "preset"
      ? { p_days: query.days, p_start: null, p_end: null }
      : { p_days: null, p_start: query.startYmd, p_end: query.endYmd }

  const { data, error } = await client.rpc("rpc_v1_profile_insights_bootstrap", params)
  if (error) throw error
  return data as ProfileInsightsBootstrapV1
}