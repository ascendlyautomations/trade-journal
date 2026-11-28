/**
 * Shared `rpc_v1_profile_insights_bootstrap` response contract (web + iOS).
 * Query via `rpc_v1_profile_insights_bootstrap` with `{ p_days }` or `{ p_start, p_end }` (UTC dates).
 */

export type ProfileInsightsDayRange = 7 | 30 | 90

export type ProfileInsightsQuery =
  | { kind: "preset"; days: ProfileInsightsDayRange }
  | { kind: "custom"; startYmd: string; endYmd: string }

export type ProfileInsightsBootstrapV1 = {
  meta: {
    contract_version: "v1"
    days: number
    viewer_id: string
    engagement_rate_denominator?: string
    engagement_rate_definition?: string
  }
  data: {
    coverage: {
      profile_visits_since?: string | null
      content_views_since?: string | null
      follower_events_since?: string | null
      shares_since?: string | null
    }
    period: {
      start: string
      end: string
      prior_start: string
      prior_end: string
    }
    summary: ProfileInsightsPeriodSummary
    summary_prior: ProfileInsightsPeriodSummary
    series: {
      profile_views_per_day?: { day: string; count: number }[]
      unique_visitors_per_day?: { day: string; count: number }[]
      content_views_per_day?: { day: string; count: number }[]
      follower_net_per_day?: { day: string; count: number }[]
      new_followers_per_day?: { day: string; count: number }[]
      unfollows_per_day?: { day: string; count: number }[]
    }
    content_views_by_kind?: Record<string, number>
    top_content?: TopContentRow[]
    top_content_by_views?: TopContentRow[]
    top_content_by_engagement?: TopContentRow[]
  }
}

export type TopContentRow = {
  content_kind: string
  content_id: string
  views: number
  engagement: number
}

export type ProfileInsightsPeriodSummary = {
  profile_views?: number
  unique_visitors?: number
  content_views?: number
  content_unique_viewers?: number
  new_followers?: number
  unfollows?: number
  net_followers?: number
  likes?: number
  comments?: number
  saves?: number
  shares_initiated?: number
  shares_completed?: number
  total_engagement?: number
  engagement_rate?: number | null
}