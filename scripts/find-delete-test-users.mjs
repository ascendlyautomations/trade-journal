import { createClient } from "@supabase/supabase-js"
import { readFileSync } from "node:fs"
import { resolve } from "node:path"

function loadEnv() {
  const raw = readFileSync(resolve(process.cwd(), ".env.local"), "utf8")
  const env = {}
  for (const line of raw.split(/\r?\n/)) {
    if (!line || line.startsWith("#")) continue
    const i = line.indexOf("=")
    if (i < 1) continue
    env[line.slice(0, i).trim()] = line.slice(i + 1).trim()
  }
  return env
}

const env = loadEnv()
const sb = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY)

const { data: admins } = await sb.from("admin_users").select("user_id")
const adminIds = new Set((admins ?? []).map((a) => a.user_id))

async function topBy(table, col, limit = 5) {
  const { data } = await sb.from(table).select(col).limit(1000)
  const counts = {}
  for (const row of data ?? []) {
    const id = row[col]
    if (!id || adminIds.has(id)) continue
    counts[id] = (counts[id] ?? 0) + 1
  }
  const sorted = Object.entries(counts).sort((a, b) => b[1] - a[1]).slice(0, limit)
  const out = []
  for (const [id, count] of sorted) {
    const { data: p } = await sb
      .from("profiles")
      .select("username")
      .eq("id", id)
      .maybeSingle()
    out.push({ id, count, username: p?.username ?? "?" })
  }
  return out
}

console.log("admin ids:", [...adminIds])
console.log("trades:", await topBy("trades", "user_id"))
console.log("posts:", await topBy("posts", "user_id"))
console.log("rooms:", await topBy("rooms", "owner_user_id"))
