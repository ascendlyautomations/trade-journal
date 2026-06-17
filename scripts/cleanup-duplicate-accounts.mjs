/**
 * Audit and remove duplicate accounts (same user_id + lower(trim(name))).
 * Keeps oldest by created_at. Reassigns trades before delete.
 *
 * Usage: node scripts/cleanup-duplicate-accounts.mjs [--apply]
 */
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"
import { createClient } from "@supabase/supabase-js"

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(__dirname, "..")
const apply = process.argv.includes("--apply")

function loadEnv() {
  const text = fs.readFileSync(path.join(root, ".env.local"), "utf8")
  return Object.fromEntries(
    text
      .split(/\r?\n/)
      .filter((line) => line && !line.startsWith("#"))
      .map((line) => {
        const index = line.indexOf("=")
        return [line.slice(0, index), line.slice(index + 1)]
      })
  )
}

function normName(name) {
  return String(name ?? "").trim().toLowerCase()
}

function groupDuplicates(rows) {
  const groups = new Map()
  for (const row of rows) {
    const key = `${row.user_id}::${normName(row.name)}`
    if (!groups.has(key)) groups.set(key, [])
    groups.get(key).push(row)
  }
  return [...groups.entries()]
    .filter(([, items]) => items.length > 1)
    .map(([key, items]) => {
      const sorted = [...items].sort((a, b) => {
        const ta = new Date(a.created_at).getTime()
        const tb = new Date(b.created_at).getTime()
        if (ta !== tb) return ta - tb
        return String(a.id).localeCompare(String(b.id))
      })
      return {
        key,
        userId: sorted[0].user_id,
        normalizedName: normName(sorted[0].name),
        displayName: sorted[0].name,
        count: sorted.length,
        keep: sorted[0],
        delete: sorted.slice(1),
      }
    })
}

async function main() {
  const env = loadEnv()
  const supabase = createClient(
    env.NEXT_PUBLIC_SUPABASE_URL,
    env.SUPABASE_SERVICE_ROLE_KEY,
    { auth: { autoRefreshToken: false, persistSession: false } }
  )

  const { data: accounts, error } = await supabase
    .from("accounts")
    .select("id,user_id,name,created_at")
    .order("created_at", { ascending: true })

  if (error) throw error

  const groups = groupDuplicates(accounts ?? [])
  const deleteIds = groups.flatMap((g) => g.delete.map((r) => r.id))
  const keepIds = groups.map((g) => g.keep.id)

  const audit = {
    totalAccounts: accounts?.length ?? 0,
    duplicateGroups: groups.length,
    rowsToDelete: deleteIds.length,
    groups: groups.map((g) => ({
      userId: g.userId,
      normalizedName: g.normalizedName,
      displayName: g.displayName,
      duplicateCount: g.count,
      keepId: g.keep.id,
      keepCreatedAt: g.keep.created_at,
      deleteIds: g.delete.map((r) => r.id),
      deleteCreatedAts: g.delete.map((r) => r.created_at),
    })),
  }

  console.log(JSON.stringify({ mode: apply ? "apply" : "audit", audit }, null, 2))

  if (!apply) {
    console.log("\nDry run only. Re-run with --apply to delete duplicates.")
    return
  }

  if (deleteIds.length === 0) {
    console.log("No duplicates to remove.")
    return
  }

  const keepByDelete = new Map()
  for (const g of groups) {
    for (const row of g.delete) {
      keepByDelete.set(row.id, g.keep.id)
    }
  }

  const { data: trades } = await supabase
    .from("trades")
    .select("id,account_id")
    .in("account_id", deleteIds)

  let tradesReassigned = 0
  for (const trade of trades ?? []) {
    const keepId = keepByDelete.get(trade.account_id)
    if (!keepId) continue
    const { error: upErr } = await supabase
      .from("trades")
      .update({ account_id: keepId })
      .eq("id", trade.id)
    if (upErr) throw upErr
    tradesReassigned += 1
  }

  const { data: profiles } = await supabase
    .from("profiles")
    .select("id,locked_account_id")
    .in("locked_account_id", deleteIds)

  let profilesUpdated = 0
  for (const profile of profiles ?? []) {
    const keepId = keepByDelete.get(profile.locked_account_id)
    if (!keepId) continue
    const { error: upErr } = await supabase
      .from("profiles")
      .update({ locked_account_id: keepId })
      .eq("id", profile.id)
    if (upErr) throw upErr
    profilesUpdated += 1
  }

  const { error: delErr, count } = await supabase
    .from("accounts")
    .delete({ count: "exact" })
    .in("id", deleteIds)

  if (delErr) throw delErr

  console.log(
    JSON.stringify(
      {
        applied: true,
        duplicateGroupsRemoved: groups.length,
        rowsDeleted: count ?? deleteIds.length,
        tradesReassigned,
        profilesUpdated,
        deletedIds: deleteIds,
        keptIds: keepIds,
      },
      null,
      2
    )
  )
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
