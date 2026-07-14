/**
 * Full user FK dependency audit (read-only).
 * Lists tables/columns referencing auth.users or profiles.
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

const env = loadEnv()
const supabase = createClient(
  env.NEXT_PUBLIC_SUPABASE_URL,
  env.SUPABASE_SERVICE_ROLE_KEY
)

/** Canonical dependency map from migrations + live schema probes. */
const DEPENDENCIES = [
  {
    table: "profiles",
    columns: [
      { column: "id", ref: "auth.users.id", cleanup: "delete row (target)" },
      { column: "banned_by", ref: "profiles.id", cleanup: "null banned_by refs" },
    ],
  },
  {
    table: "admin_users",
    columns: [{ column: "user_id", ref: "auth.users.id", cleanup: "block delete" }],
  },
  {
    table: "admin_audit_log",
    columns: [
      { column: "admin_user_id", ref: "auth.users.id", cleanup: "cascade on auth delete" },
      {
        column: "target_user_id",
        ref: "profiles.id (prod) / auth.users",
        cleanup: "insert audit before profile delete",
      },
    ],
  },
  {
    table: "trades",
    columns: [{ column: "user_id", ref: "auth.users / profiles", cleanup: "delete by user_id" }],
  },
  {
    table: "posts",
    columns: [{ column: "user_id", ref: "auth.users", cleanup: "delete by user_id" }],
  },
  {
    table: "likes",
    columns: [
      { column: "user_id", ref: "profiles (prod)", cleanup: "delete by user_id" },
      { column: "post_id", ref: "posts.id", cleanup: "delete on owned posts" },
    ],
  },
  {
    table: "comments",
    columns: [
      { column: "user_id", ref: "auth.users", cleanup: "delete by user_id" },
      { column: "post_id", ref: "posts.id", cleanup: "delete on owned posts" },
    ],
  },
  {
    table: "trade_likes",
    columns: [
      { column: "user_id", ref: "auth.users", cleanup: "delete by user_id" },
      { column: "trade_id", ref: "trades.id", cleanup: "delete on owned trades" },
    ],
  },
  {
    table: "trade_comments",
    columns: [
      { column: "user_id", ref: "auth.users", cleanup: "delete by user_id" },
      { column: "trade_id", ref: "trades.id", cleanup: "delete on owned trades" },
    ],
  },
  {
    table: "notifications",
    columns: [
      { column: "user_id", ref: "auth.users", cleanup: "delete by user_id" },
      { column: "sender_id", ref: "auth.users", cleanup: "delete by sender_id" },
      { column: "post_id", ref: "posts.id", cleanup: "delete on owned posts" },
      { column: "trade_id", ref: "trades.id", cleanup: "delete on owned trades" },
    ],
  },
  {
    table: "messages",
    columns: [
      { column: "sender_id", ref: "auth.users", cleanup: "delete by sender_id" },
      { column: "user_id", ref: "auth.users", cleanup: "delete by user_id" },
      { column: "trade_id", ref: "trades.id", cleanup: "delete on owned trades" },
    ],
  },
  {
    table: "message_likes",
    columns: [
      { column: "user_id", ref: "auth.users", cleanup: "delete by user_id" },
      { column: "message_id", ref: "messages.id", cleanup: "delete on user messages" },
    ],
  },
  {
    table: "message_comments",
    columns: [
      { column: "user_id", ref: "auth.users", cleanup: "delete by user_id" },
      { column: "message_id", ref: "messages.id", cleanup: "delete on user messages" },
    ],
  },
  {
    table: "message_deletions",
    columns: [{ column: "user_id", ref: "auth.users", cleanup: "delete by user_id" }],
  },
  {
    table: "conversation_participants",
    columns: [{ column: "user_id", ref: "auth.users", cleanup: "delete by user_id" }],
  },
  {
    table: "rooms",
    columns: [
      { column: "owner_user_id", ref: "profiles.id", cleanup: "delete owned rooms cascade" },
    ],
  },
  {
    table: "room_messages",
    columns: [
      { column: "user_id", ref: "profiles.id (prod)", cleanup: "delete by user_id" },
      { column: "room_id", ref: "rooms.id", cleanup: "delete in owned rooms" },
      { column: "trade_id", ref: "trades.id", cleanup: "delete on owned trades" },
      { column: "pinned_trade_id", ref: "trades.id", cleanup: "delete on owned trades" },
    ],
  },
  {
    table: "room_members",
    columns: [
      { column: "user_id", ref: "profiles.id", cleanup: "delete by user_id" },
      { column: "room_id", ref: "rooms.id", cleanup: "delete in owned rooms" },
    ],
  },
  {
    table: "room_bans",
    columns: [
      { column: "user_id", ref: "profiles.id", cleanup: "delete by user_id" },
      { column: "banned_by", ref: "profiles.id", cleanup: "delete bans issued by user" },
      { column: "room_id", ref: "rooms.id", cleanup: "delete in owned rooms" },
    ],
  },
  {
    table: "room_presence",
    columns: [
      { column: "user_id", ref: "auth.users / profiles", cleanup: "delete by user_id" },
      { column: "room_id", ref: "rooms.id", cleanup: "delete in owned rooms" },
    ],
  },
  {
    table: "room_sections",
    columns: [{ column: "room_id", ref: "rooms.id", cleanup: "delete in owned rooms" }],
  },
  {
    table: "followers",
    columns: [
      { column: "follower_id", ref: "auth.users", cleanup: "delete either side" },
      { column: "following_id", ref: "profiles.id", cleanup: "delete either side" },
    ],
  },
  {
    table: "follow_requests",
    columns: [
      { column: "requester_id", ref: "auth.users", cleanup: "delete either side" },
      { column: "target_id", ref: "profiles.id", cleanup: "delete either side" },
    ],
  },
  {
    table: "profile_posts",
    columns: [{ column: "user_id", ref: "profiles.id", cleanup: "delete by user_id" }],
  },
  {
    table: "stories",
    columns: [{ column: "user_id", ref: "profiles.id", cleanup: "delete by user_id" }],
  },
  {
    table: "saved_posts",
    columns: [
      { column: "user_id", ref: "auth.users", cleanup: "delete by user_id" },
      { column: "post_id", ref: "posts.id", cleanup: "delete on owned posts" },
    ],
  },
  {
    table: "saved_trades",
    columns: [
      { column: "user_id", ref: "auth.users", cleanup: "delete by user_id" },
      { column: "trade_id", ref: "trades.id", cleanup: "delete on owned trades" },
    ],
  },
  {
    table: "affiliates",
    columns: [{ column: "user_id", ref: "auth.users", cleanup: "delete by user_id" }],
  },
  {
    table: "affiliate_applications",
    columns: [
      { column: "user_id", ref: "auth.users", cleanup: "delete by user_id" },
      { column: "reviewed_by", ref: "auth.users", cleanup: "null reviewed_by" },
    ],
  },
  {
    table: "affiliate_payout_requests",
    columns: [
      { column: "user_id", ref: "auth.users", cleanup: "delete by user_id" },
      { column: "reviewed_by", ref: "auth.users", cleanup: "null reviewed_by" },
    ],
  },
  {
    table: "referrals",
    columns: [
      { column: "referrer_user_id", ref: "profiles.id", cleanup: "optional delete" },
      { column: "referred_user_id", ref: "profiles.id", cleanup: "optional delete" },
    ],
  },
  {
    table: "referrals_ledger",
    columns: [
      { column: "referrer_user_id", ref: "profiles.id", cleanup: "optional delete" },
      { column: "referred_user_id", ref: "profiles.id", cleanup: "optional delete" },
    ],
  },
  {
    table: "achievements",
    columns: [{ column: "user_id", ref: "auth.users", cleanup: "delete by user_id" }],
  },
  {
    table: "feedback_submissions",
    columns: [{ column: "user_id", ref: "auth.users", cleanup: "delete by user_id" }],
  },
  {
    table: "support_tickets",
    columns: [{ column: "user_id", ref: "auth.users", cleanup: "delete by user_id" }],
  },
  {
    table: "bug_reports",
    columns: [{ column: "user_id", ref: "auth.users", cleanup: "delete by user_id" }],
  },
  {
    table: "feature_requests",
    columns: [{ column: "user_id", ref: "auth.users", cleanup: "delete by user_id" }],
  },
  {
    table: "presets",
    columns: [{ column: "user_id", ref: "auth.users", cleanup: "delete by user_id" }],
  },
  {
    table: "accounts",
    columns: [{ column: "user_id", ref: "profiles.id", cleanup: "delete by user_id" }],
  },
  {
    table: "user_accounts",
    columns: [{ column: "user_id", ref: "auth.users", cleanup: "delete by user_id" }],
  },
  {
    table: "creator_code_redemptions",
    columns: [{ column: "user_id", ref: "auth.users", cleanup: "delete by user_id" }],
  },
  {
    table: "csv_support_requests",
    columns: [{ column: "user_id", ref: "auth.users", cleanup: "delete by user_id" }],
  },
  {
    table: "account_settings",
    columns: [
      { column: "id", ref: "auth.users.id", cleanup: "optional delete row" },
      { column: "banned_by", ref: "profiles.id", cleanup: "null banned_by" },
    ],
  },
  {
    table: "billing_accounts",
    columns: [{ column: "id", ref: "auth.users.id", cleanup: "optional delete row" }],
  },
]

async function probeTable(table) {
  const { error } = await supabase.from(table).select("*", { head: true, count: "exact" })
  return {
    exists: !error || error.code !== "PGRST205",
    error: error?.code === "PGRST205" ? null : error?.message ?? null,
  }
}

async function main() {
  const report = {
    generatedAt: new Date().toISOString(),
    tables: [],
    missingInProd: [],
  }

  for (const entry of DEPENDENCIES) {
    const probe = await probeTable(entry.table)
    if (!probe.exists) {
      report.missingInProd.push(entry.table)
      continue
    }
    report.tables.push({
      ...entry,
      prodExists: true,
      probeError: probe.error,
    })
  }

  console.log(JSON.stringify(report, null, 2))
  console.error(
    `\nTotal tables: ${DEPENDENCIES.length}, present in prod: ${report.tables.length}, missing: ${report.missingInProd.length}`
  )
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
