import type { SupabaseClient } from "@supabase/supabase-js"
import {
  PRODUCT_ANALYTICS_EVENTS,
  PRODUCT_ANALYTICS_PLATFORM,
  type ProductAnalyticsEventName,
} from "./constants"

const SESSION_STORAGE_KEY = "tt.product.session_id"
const SESSION_STARTED_KEY = "tt.product.session_started"
const APP_OPEN_BUCKET_KEY = "tt.product.app_open_hour"
const MAX_BATCH = 25
const FLUSH_MS = 12_000

export type ProductAnalyticsPayload = {
  event_name: ProductAnalyticsEventName
  platform: typeof PRODUCT_ANALYTICS_PLATFORM
  session_id: string
  occurred_at?: string
  dedupe_key?: string
  props?: Record<string, string>
}

let flushTimer: ReturnType<typeof setTimeout> | null = null
let queue: ProductAnalyticsPayload[] = []
let client: SupabaseClient | null = null
let flushing = false

function readSessionId(): string {
  if (typeof window === "undefined") return crypto.randomUUID()
  try {
    const existing = window.sessionStorage.getItem(SESSION_STORAGE_KEY)
    if (existing && /^[0-9a-f-]{36}$/i.test(existing)) return existing
    const created = crypto.randomUUID()
    window.sessionStorage.setItem(SESSION_STORAGE_KEY, created)
    return created
  } catch {
    return crypto.randomUUID()
  }
}

function utcHourBucket(): string {
  const d = new Date()
  return `${d.getUTCFullYear()}-${d.getUTCMonth()}-${d.getUTCDate()}-${d.getUTCHours()}`
}

function enqueue(payload: ProductAnalyticsPayload) {
  queue.push(payload)
  if (queue.length >= MAX_BATCH) {
    void flushProductAnalytics()
    return
  }
  if (flushTimer) return
  flushTimer = setTimeout(() => {
    flushTimer = null
    void flushProductAnalytics()
  }, FLUSH_MS)
}

export function configureProductAnalytics(supabase: SupabaseClient | null) {
  client = supabase
}

export function trackProductAnalytics(
  eventName: ProductAnalyticsEventName,
  props: Record<string, string> = {},
  dedupeKey?: string
) {
  if (!client) return
  const payload: ProductAnalyticsPayload = {
    event_name: eventName,
    platform: PRODUCT_ANALYTICS_PLATFORM,
    session_id: readSessionId(),
    props,
  }
  if (dedupeKey) payload.dedupe_key = dedupeKey.slice(0, 256)
  enqueue(payload)
}

export function productAnalyticsSessionStarted() {
  if (typeof window === "undefined") return
  try {
    if (window.sessionStorage.getItem(SESSION_STARTED_KEY) === "1") return
    window.sessionStorage.setItem(SESSION_STARTED_KEY, "1")
  } catch {
    // ignore
  }
  trackProductAnalytics(
    PRODUCT_ANALYTICS_EVENTS.sessionStarted,
    {},
    `session_started:${readSessionId()}`
  )
}

export function productAnalyticsAppOpened() {
  const hour = utcHourBucket()
  try {
    if (typeof window !== "undefined") {
      const prev = window.sessionStorage.getItem(APP_OPEN_BUCKET_KEY)
      if (prev === hour) return
      window.sessionStorage.setItem(APP_OPEN_BUCKET_KEY, hour)
    }
  } catch {
    // ignore
  }
  trackProductAnalytics(
    PRODUCT_ANALYTICS_EVENTS.appOpened,
    {},
    `app_opened:${hour}`
  )
}

export function productAnalyticsScreenViewed(screenId: string) {
  const hour = utcHourBucket()
  const sid = readSessionId()
  trackProductAnalytics(
    PRODUCT_ANALYTICS_EVENTS.screenViewed,
    { screen_id: screenId },
    `screen:${sid}:${screenId}:${hour}`
  )
}

export function productAnalyticsProfileViewed(profileId: string) {
  const day = new Date().toISOString().slice(0, 10)
  trackProductAnalytics(
    PRODUCT_ANALYTICS_EVENTS.profileViewed,
    { profile_id: profileId },
    `profile_view:${readSessionId()}:${profileId}:${day}`
  )
}

export function productAnalyticsFeatureUsed(featureKey: string) {
  const sid = readSessionId()
  trackProductAnalytics(
    PRODUCT_ANALYTICS_EVENTS.featureUsed,
    { feature: featureKey },
    `feature:${sid}:${featureKey}`
  )
}

export async function flushProductAnalytics(): Promise<void> {
  if (flushing || !client || queue.length === 0) return
  flushing = true
  const batch = queue.splice(0, MAX_BATCH)
  try {
    await client.rpc("rpc_v1_product_events_ingest", { p_batch: batch })
  } catch {
    // Never block UX — drop failed batch
  } finally {
    flushing = false
    if (queue.length > 0) void flushProductAnalytics()
  }
}

if (typeof window !== "undefined") {
  window.addEventListener("pagehide", () => {
    void flushProductAnalytics()
  })
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden") void flushProductAnalytics()
  })
}