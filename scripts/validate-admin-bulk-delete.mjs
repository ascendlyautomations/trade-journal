/**
 * Validates bulk delete flow (iterates deleteUserAdmin like the admin UI API route).
 * WARNING: permanently deletes listed users.
 */
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
    let val = line.slice(i + 1).trim()
    if (
      (val.startsWith('"') && val.endsWith('"')) ||
      (val.startsWith("'") && val.endsWith("'"))
    ) {
      val = val.slice(1, -1)
    }
    env[line.slice(0, i).trim()] = val
  }
  return env
}

const env = loadEnv()
const sb = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY)
const { deleteUserAdmin, AdminUserDeletionError } = await import("../lib/deleteUserAdmin.ts")

async function findEmptyUsers(adminId, limit = 5) {
  const { data: profiles } = await sb
    .from("profiles")
    .select("id, username")
    .neq("id", adminId)
    .limit(40)
  const out = []
  for (const p of profiles ?? []) {
    const checks = await Promise.all(
      ["trades", "posts", "room_messages", "rooms"].map(async (table) => {
        const col = table === "rooms" ? "owner_user_id" : "user_id"
        const { count } = await sb
          .from(table)
          .select("*", { count: "exact", head: true })
          .eq(col, p.id)
        return count ?? 0
      })
    )
    if (checks.every((c) => c === 0)) out.push(p)
    if (out.length >= limit) break
  }
  return out
}

async function main() {
  const { data: admins } = await sb.from("admin_users").select("user_id").limit(1)
  const adminId = admins?.[0]?.user_id
  if (!adminId) throw new Error("No admin")

  const emptyUsers = await findEmptyUsers(adminId, 5)
  console.log(
    "empty users for bulk test:",
    emptyUsers.map((u) => u.username)
  )
  if (emptyUsers.length < 3) {
    console.error("Need at least 3 empty users")
    process.exit(1)
  }

  const batch = emptyUsers.slice(0, 5)
  const outcome = { deleted: [], skipped: [], failed: [] }

  const targets = [{ id: adminId, username: "admin-self" }, ...batch]

  for (const u of targets) {
    if (u.id === adminId) {
      try {
        await deleteUserAdmin(sb, { adminUserId: adminId, targetUserId: u.id, stripe: null })
        outcome.failed.push({ username: u.username, message: "self-delete should have failed" })
      } catch (err) {
        if (err instanceof AdminUserDeletionError && err.code === "SELF_DELETE") {
          outcome.skipped.push({ username: u.username, reason: err.message })
        } else {
          outcome.failed.push({
            username: u.username,
            message: err instanceof Error ? err.message : String(err),
          })
        }
      }
      continue
    }

    try {
      await deleteUserAdmin(sb, { adminUserId: adminId, targetUserId: u.id, stripe: null })
      outcome.deleted.push(u.username)
      const { data: prof } = await sb.from("profiles").select("id").eq("id", u.id).maybeSingle()
      const { data: auth } = await sb.auth.admin.getUserById(u.id)
      const { data: audit } = await sb
        .from("admin_audit_log")
        .select("id")
        .eq("target_id", u.id)
        .eq("action", "delete_user")
        .limit(1)
      if (prof?.id || auth?.user?.id || !audit?.length) {
        outcome.failed.push({
          username: u.username,
          message: `orphan check prof=${!!prof?.id} auth=${!!auth?.user?.id} audit=${!!audit?.length}`,
        })
      }
    } catch (err) {
      outcome.failed.push({
        username: u.username,
        message: err instanceof Error ? err.message : String(err),
      })
    }
  }

  console.log("\n=== BULK DELETE VALIDATION ===")
  console.log(JSON.stringify(outcome, null, 2))
  if (outcome.failed.length > 0) process.exit(1)
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
