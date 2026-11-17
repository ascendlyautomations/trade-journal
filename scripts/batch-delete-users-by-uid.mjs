/**
 * Batch permanent user deletion by explicit UID list (admin pipeline only).
 *
 * SAFETY:
 * - Default mode is preview-only (no mutations).
 * - Never discovers or selects users by email domain, age, or activity.
 * - Requires a real admin user id (member of admin_users) for --execute.
 * - Execution requires typing DELETE after preview (or BATCH_DELETE_CONFIRM=DELETE).
 * - Loads SUPABASE_SERVICE_ROLE_KEY from .env.local on your machine only — never commit keys.
 *
 * Usage:
 *   node scripts/batch-delete-users-by-uid.mjs <uid> [uid2 ...]
 *   node scripts/batch-delete-users-by-uid.mjs --file ./uids.txt
 *   node scripts/batch-delete-users-by-uid.mjs --file ./uids.txt --execute --admin <admin-user-uuid>
 *
 * UID file: one UUID per line; # comments and blank lines ignored.
 */
import { createInterface } from "node:readline/promises"
import { readFileSync } from "node:fs"
import { resolve } from "node:path"
import { stdin as input, stdout as output } from "node:process"
import { createClient } from "@supabase/supabase-js"

function loadEnv() {
  const raw = readFileSync(resolve(process.cwd(), ".env.local"), "utf8")
  const env = {}
  for (const line of raw.split(/\r?\n/)) {
    if (!line || line.startsWith("#")) continue
    const i = line.indexOf("=")
    if (i < 1) continue
    const key = line.slice(0, i).trim()
    let val = line.slice(i + 1).trim()
    if (
      (val.startsWith('"') && val.endsWith('"')) ||
      (val.startsWith("'") && val.endsWith("'"))
    ) {
      val = val.slice(1, -1)
    }
    env[key] = val
  }
  return env
}

function parseArgs(argv) {
  const uids = []
  let file = null
  let execute = false
  let adminId = null
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    if (arg === "--file") {
      file = argv[++i]
      continue
    }
    if (arg === "--execute") {
      execute = true
      continue
    }
    if (arg === "--admin") {
      adminId = argv[++i]?.trim() ?? null
      continue
    }
    if (arg.startsWith("-")) {
      throw new Error(`Unknown flag: ${arg}`)
    }
    uids.push(arg.trim())
  }
  if (file) {
    const text = readFileSync(resolve(process.cwd(), file), "utf8")
    for (const line of text.split(/\r?\n/)) {
      const t = line.replace(/#.*$/, "").trim()
      if (t) uids.push(t)
    }
  }
  const unique = [...new Set(uids.filter(Boolean))]
  if (unique.length === 0) {
    throw new Error("Provide at least one UID via arguments or --file")
  }
  return { uids: unique, execute, adminId }
}

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

async function extraCounts(sb, userId) {
  const tables = [
    ["broker_integration_connections", "user_id"],
    ["broker_integration_accounts", "user_id"],
    ["trader_daily_check_ins", "user_id"],
    ["vault_items", "user_id"],
    ["vault_folders", "user_id"],
    ["accounts", "user_id"],
    ["user_accounts", "user_id"],
    ["rooms", "owner_user_id"],
    ["room_members", "user_id"],
  ]
  const out = {}
  for (const [table, col] of tables) {
    const { count, error } = await sb
      .from(table)
      .select("*", { count: "exact", head: true })
      .eq(col, userId)
    out[`${table}.${col}`] = error ? `error: ${error.message}` : (count ?? 0)
  }
  return out
}

function printPreviewRow(preview, extra) {
  console.log("\n---")
  console.log("UID:", preview.userId)
  console.log("Email:", preview.email ?? "(none)")
  console.log("Username:", preview.username ?? "(none)")
  console.log("Created:", preview.createdAt ?? "(unknown)")
  console.log("Trades:", preview.tradeCount)
  console.log("Posts:", preview.postCount)
  console.log("Comments:", preview.commentCount)
  console.log("Messages:", preview.messageCount)
  console.log("Rooms owned:", preview.roomOwnershipCount)
  console.log("Followers:", preview.followerCount)
  console.log("Stripe customer:", preview.stripeCustomerId ?? "(none)")
  console.log("Subscription:", preview.subscriptionStatus ?? "(none)")
  console.log("Affiliate:", preview.affiliateStatus ?? "(none)")
  console.log("Related (extra):", extra)
}

async function main() {
  const { uids, execute, adminId } = parseArgs(process.argv.slice(2))

  for (const id of uids) {
    if (!UUID_RE.test(id)) {
      throw new Error(`Invalid UUID: ${id}`)
    }
  }

  const env = loadEnv()
  if (!env.NEXT_PUBLIC_SUPABASE_URL || !env.SUPABASE_SERVICE_ROLE_KEY) {
    throw new Error("Missing NEXT_PUBLIC_SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in .env.local")
  }

  const sb = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY)
  const { fetchAdminUserDeletionPreview } = await import(
    "../lib/adminUserDeletionPreview.ts"
  )
  const { deleteUserAdmin, AdminUserDeletionError, AdminUserDeletionStepError } =
    await import("../lib/deleteUserAdmin.ts")

  const { data: adminRows } = await sb.from("admin_users").select("user_id")
  const adminIds = new Set((adminRows ?? []).map((r) => r.user_id))

  console.log("Mode:", execute ? "EXECUTE (destructive)" : "PREVIEW ONLY")
  console.log("Target UIDs:", uids.length)

  const previews = []
  for (const userId of uids) {
    if (adminIds.has(userId)) {
      console.log(`\nSKIP (admin account): ${userId}`)
      continue
    }
    const { preview, error } = await fetchAdminUserDeletionPreview(sb, userId)
    if (!preview) {
      console.log(`\nNOT FOUND: ${userId} — ${error ?? "unknown"}`)
      continue
    }
    const extra = await extraCounts(sb, userId)
    printPreviewRow(preview, extra)
    previews.push(preview)
  }

  if (!execute) {
    console.log("\n=== Preview complete. Re-run with --execute --admin <admin-uuid> to delete. ===")
    return
  }

  if (!adminId || !UUID_RE.test(adminId)) {
    throw new Error("--execute requires --admin <valid-admin-user-uuid>")
  }
  if (!adminIds.has(adminId)) {
    throw new Error("--admin user is not in admin_users")
  }
  if (previews.some((p) => p.userId === adminId)) {
    throw new Error("Admin uid cannot appear in the delete list")
  }

  const confirmEnv = process.env.BATCH_DELETE_CONFIRM
  let confirmed = confirmEnv === "DELETE"
  if (!confirmed) {
    const rl = createInterface({ input, output })
    const typed = await rl.question(
      `Type DELETE to permanently remove ${previews.length} account(s): `
    )
    rl.close()
    confirmed = typed.trim() === "DELETE"
  }
  if (!confirmed) {
    console.log("Aborted — confirmation not provided.")
    process.exit(1)
  }

  let stripe = null
  if (process.env.STRIPE_SECRET_KEY) {
    try {
      const { getStripeServer } = await import("../lib/stripeServer.ts")
      stripe = getStripeServer()
    } catch (err) {
      console.warn(
        "Stripe unavailable; continuing without subscription cancel:",
        err instanceof Error ? err.message : err
      )
    }
  }

  const outcome = { deleted: [], skipped: [], failed: [] }

  for (const preview of previews) {
    const label = `${preview.username ?? "?"} (${preview.userId})`
    try {
      await deleteUserAdmin(sb, {
        adminUserId: adminId,
        targetUserId: preview.userId,
        stripe,
      })
      const { data: prof } = await sb.from("profiles").select("id").eq("id", preview.userId).maybeSingle()
      const { data: auth } = await sb.auth.admin.getUserById(preview.userId)
      if (prof?.id || auth?.user?.id) {
        outcome.failed.push({
          id: preview.userId,
          label,
          message: `orphan check profile=${!!prof?.id} auth=${!!auth?.user?.id}`,
        })
      } else {
        outcome.deleted.push({ id: preview.userId, label })
      }
    } catch (err) {
      if (err instanceof AdminUserDeletionError) {
        outcome.skipped.push({
          id: preview.userId,
          label,
          reason: `${err.code}: ${err.message}`,
        })
      } else if (err instanceof AdminUserDeletionStepError) {
        outcome.failed.push({
          id: preview.userId,
          label,
          step: err.step,
          table: err.table,
          message: err.message,
        })
      } else {
        outcome.failed.push({
          id: preview.userId,
          label,
          message: err instanceof Error ? err.message : String(err),
        })
      }
    }
  }

  console.log("\n=== BATCH DELETE RESULT ===")
  console.log(JSON.stringify(outcome, null, 2))
  if (outcome.failed.length > 0) process.exit(1)
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})