/**
 * Load-test workload taxonomy — label results; do not conflate with production UX.
 */

export const WORKLOAD_SUPABASE_DIRECT = "supabase_direct"
export const WORKLOAD_CLIENT_REALISTIC = "client_realistic"
export const WORKLOAD_REALISTIC150 = "realistic150_ios"

export const WORKLOAD_LABELS = {
  [WORKLOAD_SUPABASE_DIRECT]: {
    short: "supabase_direct",
    title: "Supabase direct (PostgREST RPC/REST stress)",
    represents:
      "Worst-case database/API path: every call hits PostgREST with no web/iOS in-memory cache or single-flight.",
    web: "Does NOT represent typical web Feed UX (browser cache + single-flight dedupe first page).",
    ios: "Does NOT represent typical iOS Feed UX (FeedSessionStore + loader dedupe on first page).",
    use: "Find Postgres/PostgREST bottlenecks and tail latency under parallel identical RPCs.",
  },
  [WORKLOAD_CLIENT_REALISTIC]: {
    short: "client_realistic",
    title: "Client-realistic (Supabase calls, app-shaped pacing & scope)",
    represents:
      "Same transport as mobile/web clients (Supabase JWT → PostgREST), with following-first Feed scope, mixed surface weights, and stage startup jitter.",
    web: "Approximates web read mix and Feed scope after session resolution; still no browser cache hits.",
    ios: "Approximates iOS RPC mix and FeedSessionStore miss path (network fetch); still no on-device cache hits.",
    use: "Capacity planning for real user mixes — not a substitute for RUM or server-side metrics.",
  },
  [WORKLOAD_REALISTIC150]: {
    short: "realistic150_ios",
    title: "Realistic 150 VU iOS mix (cached screens + natural idle)",
    represents:
      "150 concurrent virtual sessions on 50 auth accounts; weighted Feed/Dashboard/Profile/Calendar/idle; 10–60s think time; per-VU screen TTL skips redundant fetches.",
    web: "Not a web workload.",
    ios: "Approximates iOS tab mix, FeedSessionStore TTL, and background idle — still PostgREST, no media downloads.",
    use: "Sustained production read capacity under natural concurrency (contrast with onefifty stress mix).",
  },
}

export function parseWorkloadKind(raw) {
  const value = String(raw || WORKLOAD_SUPABASE_DIRECT)
    .trim()
    .toLowerCase()
  if (value === WORKLOAD_CLIENT_REALISTIC) {
    return WORKLOAD_CLIENT_REALISTIC
  }
  if (value === WORKLOAD_REALISTIC150) {
    return WORKLOAD_REALISTIC150
  }
  if (value === WORKLOAD_SUPABASE_DIRECT) {
    return WORKLOAD_SUPABASE_DIRECT
  }
  throw new Error(
    "LOADTEST_WORKLOAD_KIND must be supabase_direct, client_realistic, or realistic150_ios (got " +
      value +
      ")"
  )
}

export function workloadSummaryLines(kind) {
  const meta = WORKLOAD_LABELS[kind]
  if (!meta) {
    return ["workload_kind: unknown"]
  }
  return [
    "workload_kind: " + meta.short,
    "workload_title: " + meta.title,
    "represents: " + meta.represents,
    "web: " + meta.web,
    "ios: " + meta.ios,
    "use: " + meta.use,
  ]
}
