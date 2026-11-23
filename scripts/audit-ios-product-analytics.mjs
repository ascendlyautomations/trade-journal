#!/usr/bin/env node
/**
 * Production audit: iOS vs web product_events and rollups.
 */
import { createClient } from "@supabase/supabase-js"
import { readFileSync, existsSync } from "node:fs"

function loadEnvLocal() {
  const path = new URL("../.env.local", import.meta.url)
  if (!existsSync(path)) return
  for (const line of readFileSync(path, "utf8").split("\n")) {
    const m = line.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/)
    if (!m) continue
    let v = m[2].trim()
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
      v = v.slice(1, -1)
    }
    if (!(m[1] in process.env)) process.env[m[1]] = v
  }
}

loadEnvLocal()

const url = process.env.NEXT_PUBLIC_SUPABASE_URL
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY

if (!url || !serviceKey) {
  console.error("FAIL: missing env")
  process.exit(1)
}

const projectRef = url.match(/https:\/\/([^.]+)\.supabase\.co/)?.[1]
console.log("Supabase URL project ref:", projectRef)

const admin = createClient(url, serviceKey, {
  auth: { autoRefreshToken: false, persistSession: false },
})

async function countEvents(platform) {
  const { count, error } = await admin
    .from("product_events")
    .select("*", { count: "exact", head: true })
    .eq("platform", platform)
  return { count: count ?? 0, error: error?.message }
}

async function recentEvents(platform, limit = 5) {
  const { data, error } = await admin
    .from("product_events")
    .select("event_name,platform,occurred_at,user_id")
    .eq("platform", platform)
    .order("occurred_at", { ascending: false })
    .limit(limit)
  return { data: data ?? [], error: error?.message }
}

async function rollupEngaged(platform) {
  const { data, error } = await admin
    .from("product_daily_user_activity")
    .select("user_id,activity_day,engaged,platforms,session_count,app_open_count,screen_view_count")
    .eq("engaged", true)
    .order("activity_day", { ascending: false })
    .limit(500)
  if (error) return { error: error.message }
  const iosEngaged = (data ?? []).filter((r) => (r.platforms ?? []).includes(platform))
  return { totalEngagedRows: data?.length ?? 0, iosEngagedRows: iosEngaged.length, sample: iosEngaged.slice(0, 3) }
}

async function featureIos() {
  const { data, error } = await admin
    .from("product_daily_feature_usage")
    .select("feature_key,activity_day,platform,unique_users,use_count")
    .eq("platform", "ios")
    .order("activity_day", { ascending: false })
    .limit(20)
  return { rows: data ?? [], error: error?.message, totalUnique: (data ?? []).reduce((s, r) => s + (r.unique_users || 0), 0) }
}

async function main() {
  const ios = await countEvents("ios")
  const web = await countEvents("web")
  const iosRecent = await recentEvents("ios")
  const rollup = await rollupEngaged("ios")
  const features = await featureIos()

  console.log(JSON.stringify({ ios, web, iosRecent, rollup, features }, null, 2))
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})