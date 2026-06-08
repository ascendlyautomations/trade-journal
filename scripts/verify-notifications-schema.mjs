import fs from "node:fs"

const env = Object.fromEntries(
  fs
    .readFileSync(".env.local", "utf8")
    .split(/\r?\n/)
    .filter((line) => line && !line.startsWith("#"))
    .map((line) => {
      const index = line.indexOf("=")
      return [line.slice(0, index), line.slice(index + 1)]
    })
)

const url = env.NEXT_PUBLIC_SUPABASE_URL
const service = env.SUPABASE_SERVICE_ROLE_KEY
const anon = env.NEXT_PUBLIC_SUPABASE_ANON_KEY

const APP_SELECT =
  "id, user_id, sender_id, type, post_id, trade_id, content, read, created_at"
const ENGAGEMENT_TYPES = ["like", "comment", "room_join", "message"]

async function rest(path, { key = service, method = "GET", body, prefer } = {}) {
  const headers = {
    apikey: key,
    Authorization: `Bearer ${key}`,
  }
  if (body) headers["Content-Type"] = "application/json"
  if (prefer) headers.Prefer = prefer
  const res = await fetch(`${url}/rest/v1/${path}`, { method, headers, body })
  const text = await res.text()
  let json
  try {
    json = text ? JSON.parse(text) : null
  } catch {
    json = text
  }
  return { status: res.status, headers: res.headers, json }
}

async function main() {
  const total = await rest("notifications?select=id", { prefer: "count=exact" })
  const totalCount = total.headers.get("content-range")?.split("/")?.[1]

  const appSelect = await rest(
    `notifications?select=${encodeURIComponent(APP_SELECT)}&order=created_at.desc&limit=200`
  )

  const navbarCount = await rest(
    "notifications?select=id&type=in.(like,comment,room_join,message)&read=eq.false",
    { prefer: "count=exact" }
  )

  const anonSelect = await rest("notifications?select=id&limit=5", { key: anon })

  const sampleUserRes = await rest("notifications?select=user_id&limit=1")
  const userId = sampleUserRes.json?.[0]?.user_id
  if (!userId) throw new Error("No notifications to test mark-as-read")

  const unreadBefore = await rest(
    `notifications?select=id&user_id=eq.${userId}&read=eq.false`,
    { prefer: "count=exact" }
  )
  const unreadBeforeCount =
    unreadBefore.headers.get("content-range")?.split("/")?.[1] ?? "0"

  const markOne = await rest(
    `notifications?select=id&user_id=eq.${userId}&read=eq.false&limit=1`
  )
  const targetId = markOne.json?.[0]?.id
  let markRead = null
  let restore = null
  if (targetId) {
    markRead = await rest(`notifications?id=eq.${targetId}`, {
      method: "PATCH",
      body: JSON.stringify({ read: true }),
      prefer: "return=representation",
    })
    restore = await rest(`notifications?id=eq.${targetId}`, {
      method: "PATCH",
      body: JSON.stringify({ read: false }),
    })
  }

  const columns = {}
  for (const column of [
    "id",
    "user_id",
    "sender_id",
    "type",
    "post_id",
    "trade_id",
    "content",
    "read",
    "created_at",
    "message",
  ]) {
    const res = await rest(`notifications?select=${column}&limit=0`)
    columns[column] = res.status === 200 ? "exists" : res.json?.message
  }

  console.log(
    JSON.stringify(
      {
        totalNotifications: totalCount,
        appSelectStatus: appSelect.status,
        appSelectRows: Array.isArray(appSelect.json) ? appSelect.json.length : 0,
        engagementTypesPresent: ENGAGEMENT_TYPES.filter((type) =>
          (appSelect.json || []).some((row) => row.type === type)
        ),
        navbarUnreadCount:
          navbarCount.headers.get("content-range")?.split("/")?.[1] ?? "?",
        anonUnauthenticatedRows: Array.isArray(anonSelect.json)
          ? anonSelect.json.length
          : anonSelect.json,
        columns,
        markRead: {
          userId,
          unreadBefore: unreadBeforeCount,
          targetId,
          patchStatus: markRead?.status,
          restoredStatus: restore?.status,
        },
        sampleRow: appSelect.json?.[0] ?? null,
      },
      null,
      2
    )
  )
}

main().catch((error) => {
  console.error(error)
  process.exit(1)
})
