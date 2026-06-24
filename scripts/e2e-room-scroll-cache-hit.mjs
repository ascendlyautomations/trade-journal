/**
 * Minimal repro: leave channel on cache-hit (no loadingMessages) — overwrite path.
 */
import { chromium } from "playwright"
import { createClient } from "@supabase/supabase-js"
import { readFileSync } from "node:fs"
import { resolve } from "node:path"

function loadEnv() {
  const raw = readFileSync(resolve(process.cwd(), ".env.local"), "utf8")
  const env = {}
  for (const line of raw.split(/\r?\n/)) {
    const trimmed = line.trim()
    if (!trimmed || trimmed.startsWith("#")) continue
    const idx = trimmed.indexOf("=")
    if (idx === -1) continue
    env[trimmed.slice(0, idx).trim()] = trimmed.slice(idx + 1).trim()
  }
  return env
}

const env = loadEnv()
const supabase = createClient(
  env.NEXT_PUBLIC_SUPABASE_URL,
  env.SUPABASE_SERVICE_ROLE_KEY,
  { auth: { autoRefreshToken: false, persistSession: false } }
)

const email = `scroll-cache-${Date.now()}@tradetraxs-test.invalid`
const password = "ScrollVerifyPass123!"
const username = `sc${String(Date.now()).slice(-8)}`
const roomSlug = `scroll-cache-${Date.now()}`

const { data: created } = await supabase.auth.admin.createUser({
  email,
  password,
  email_confirm: true,
})
const userId = created.user.id
await supabase.from("profiles").upsert({ id: userId, username, onboarding_completed: true })

const { data: room } = await supabase
  .from("rooms")
  .insert({ name: "Cache Hit Room", slug: roomSlug, owner_user_id: userId, is_private: false })
  .select("id")
  .single()
await supabase.from("room_members").upsert({ room_id: room.id, user_id: userId })

const { data: general } = await supabase
  .from("room_sections")
  .insert({ room_id: room.id, name: "general", position: 1, allow_members_chat: true })
  .select("id")
  .single()
const { data: announcements } = await supabase
  .from("room_sections")
  .insert({
    room_id: room.id,
    name: "announcements",
    position: 0,
    allow_members_chat: false,
  })
  .select("id")
  .single()

await supabase.from("room_messages").insert([
  ...Array.from({ length: 60 }, (_, i) => ({
    room_id: room.id,
    user_id: userId,
    section_id: general.id,
    content: `General ${i + 1} ${"x".repeat(40)}`,
    pinned: false,
  })),
  ...Array.from({ length: 30 }, (_, i) => ({
    room_id: room.id,
    user_id: userId,
    section_id: announcements.id,
    content: `Ann ${i + 1} ${"z".repeat(40)}`,
    pinned: false,
  })),
])

const verifyLogs = []
let browser
try {
  browser = await chromium.launch({ headless: true })
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } })
  page.on("console", (msg) => {
    const text = msg.text()
    if (text.includes("[room-scroll-verify]")) verifyLogs.push(text)
  })

  await page.goto("http://localhost:3000/login")
  await page.getByPlaceholder("Email").fill(email)
  await page.getByPlaceholder("Password").fill(password)
  await page.locator("form").getByRole("button", { name: /^Login$/i }).click()
  await page.waitForURL(/dashboard|app|community|feed/, { timeout: 45000 })
  await page.evaluate(() => {
    for (const k of Object.keys(localStorage)) {
      if (k.includes("getting_started")) localStorage.removeItem(k)
    }
  })

  await page.goto(`http://localhost:3000/community?room=${encodeURIComponent(roomSlug)}`)
  await page.waitForTimeout(2500)

  const generalBtn = page.locator(".hidden.md\\:flex").getByRole("button", { name: /^general$/i })
  const annBtn = page.locator(".hidden.md\\:flex").getByRole("button", { name: /^announcements$/i })

  // Prime announcements cache (first visit — network)
  await annBtn.click({ force: true })
  await page.waitForTimeout(2000)

  // Open general and scroll halfway
  await generalBtn.click({ force: true })
  await page.waitForTimeout(500)
  await page
    .locator(".hidden.md\\:flex")
    .locator(".bg-green-500\\/20")
    .getByRole("button", { name: /^general$/i })
    .waitFor({ timeout: 10000 })
  await page.waitForTimeout(1500)
  const scrollContainer = page
    .locator("[data-room-message-id]")
    .first()
    .locator("xpath=ancestor::div[contains(@class,'overflow-y-auto')][1]")
  const halfway = await scrollContainer.evaluate((el) => {
    const max = el.scrollHeight - el.clientHeight
    el.scrollTop = Math.round(max / 2)
    el.dispatchEvent(new Event("scroll", { bubbles: true }))
    return { scrollTop: el.scrollTop, maxScroll: max }
  })
  await page.waitForTimeout(400)

  const activeSectionBeforeLeave = await page
    .locator(".hidden.md\\:flex .bg-green-500\\/20")
    .locator("button")
    .first()
    .textContent()

  const lsBeforeLeave = await page.evaluate(
    ([roomId, generalId]) => {
      const raw = localStorage.getItem("trade-room-scroll-positions-v1")
      const store = raw ? JSON.parse(raw) : null
      const generalKey = `${roomId}::${generalId}`
      return {
        activeKey: generalKey,
        generalEntry: store?.positions?.[generalKey] ?? null,
        full: store,
      }
    },
    [room.id, general.id]
  )

  // Leave to announcements — CACHE HIT (no loadingMessages)
  await annBtn.click({ force: true })
  await page.waitForTimeout(1500)

  const lsAfterLeave = await page.evaluate(() =>
    localStorage.getItem("trade-room-scroll-positions-v1")
  )

  // Return to general — CACHE HIT
  await generalBtn.click({ force: true })
  await page.waitForTimeout(2000)

  const finalScroll = await scrollContainer.evaluate((el) => ({
    scrollTop: el.scrollTop,
    scrollHeight: el.scrollHeight,
  }))
  const lsAfterReturn = await page.evaluate(() =>
    localStorage.getItem("trade-room-scroll-positions-v1")
  )

  console.log(
    JSON.stringify(
      {
        generalSectionId: general.id,
        announcementsSectionId: announcements.id,
        halfway,
        activeSectionBeforeLeave,
        lsBeforeLeave,
        lsAfterLeave: JSON.parse(lsAfterLeave),
        lsAfterReturn: JSON.parse(lsAfterReturn),
        finalScroll,
        verifyLogs,
      },
      null,
      2
    )
  )
} finally {
  await supabase.from("rooms").delete().eq("id", room.id)
  await supabase.auth.admin.deleteUser(userId)
  if (browser) await browser.close()
}
