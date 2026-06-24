/**
 * E2E: verify trade-room scroll persistence logs (channel → leave → return).
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

const email = `scroll-verify-${Date.now()}@tradetraxs-test.invalid`
const password = "ScrollVerifyPass123!"
const username = `sv${String(Date.now()).slice(-8)}`
const roomSlug = `scroll-verify-${Date.now()}`

const { data: created, error: createErr } = await supabase.auth.admin.createUser({
  email,
  password,
  email_confirm: true,
})
if (createErr) throw createErr
const userId = created.user.id

await supabase.from("profiles").upsert({
  id: userId,
  username,
  onboarding_completed: true,
})

const { data: room, error: roomErr } = await supabase
  .from("rooms")
  .insert({
    name: "Scroll Verify Room",
    slug: roomSlug,
    owner_user_id: userId,
    is_private: false,
  })
  .select("id")
  .single()
if (roomErr) throw roomErr

await supabase.from("room_members").upsert({
  room_id: room.id,
  user_id: userId,
})

const { data: generalSection, error: genErr } = await supabase
  .from("room_sections")
  .insert({ room_id: room.id, name: "general", position: 1, allow_members_chat: true })
  .select("id")
  .single()
if (genErr) throw genErr

const { data: announcementsSection, error: annErr } = await supabase
  .from("room_sections")
  .insert({
    room_id: room.id,
    name: "announcements",
    position: 0,
    allow_members_chat: false,
  })
  .select("id")
  .single()
if (annErr) throw annErr

const messageRows = Array.from({ length: 60 }, (_, i) => ({
  room_id: room.id,
  user_id: userId,
  section_id: generalSection.id,
  content: `Scroll verify message ${i + 1} — ${"x".repeat(40)}`,
  pinned: false,
}))
const { error: msgErr } = await supabase.from("room_messages").insert(messageRows)
if (msgErr) throw msgErr

const { data: offTopicSection, error: offErr } = await supabase
  .from("room_sections")
  .insert({
    room_id: room.id,
    name: "off-topic",
    position: 2,
    allow_members_chat: true,
  })
  .select("id")
  .single()
if (offErr) throw offErr

const offTopicRows = Array.from({ length: 40 }, (_, i) => ({
  room_id: room.id,
  user_id: userId,
  section_id: offTopicSection.id,
  content: `Off-topic message ${i + 1} — ${"y".repeat(40)}`,
  pinned: false,
}))
const { error: offMsgErr } = await supabase.from("room_messages").insert(offTopicRows)
if (offMsgErr) throw offMsgErr

const annRows = Array.from({ length: 30 }, (_, i) => ({
  room_id: room.id,
  user_id: userId,
  section_id: announcementsSection.id,
  content: `Announcement ${i + 1} — ${"z".repeat(40)}`,
  pinned: false,
}))
const { error: annMsgErr } = await supabase.from("room_messages").insert(annRows)
if (annMsgErr) throw annMsgErr

console.log("seeded", {
  userId,
  roomId: room.id,
  roomSlug,
  generalSectionId: generalSection.id,
  announcementsSectionId: announcementsSection.id,
  offTopicSectionId: offTopicSection.id,
})

const verifyLogs = []
let browser
let scrollMetrics
let finalMetrics
let localStoragePayload
try {
  browser = await chromium.launch({ headless: true })
  const context = await browser.newContext({ viewport: { width: 1280, height: 900 } })
  const page = await context.newPage()

  page.on("console", (msg) => {
    const text = msg.text()
    if (text.includes("[room-scroll-verify]")) {
      verifyLogs.push(text)
    }
  })

  await page.goto("http://localhost:3000/login")
  await page.getByPlaceholder("Email").fill(email)
  await page.getByPlaceholder("Password").fill(password)
  await page.locator("form").getByRole("button", { name: /^Login$/i }).click()
  await page.waitForURL(/dashboard|app|community|feed/, { timeout: 45000 })
  await page.waitForTimeout(1500)

  await page.evaluate(() => {
    for (const k of Object.keys(localStorage)) {
      if (k.includes("getting_started")) localStorage.removeItem(k)
    }
  })

  await page.goto(`http://localhost:3000/community?room=${encodeURIComponent(roomSlug)}`)
  await page.waitForTimeout(3000)

  const modalBackdrop = page.locator(".fixed.inset-0.z-50")
  if ((await modalBackdrop.count()) > 0) {
    await page.keyboard.press("Escape")
    await page.waitForTimeout(500)
    const closeBtn = page.getByRole("button", { name: /close|dismiss|got it|continue|skip/i })
    if ((await closeBtn.count()) > 0) {
      await closeBtn.first().click()
      await page.waitForTimeout(500)
    }
  }

  const generalBtn = page
    .locator(".hidden.md\\:flex")
    .getByRole("button", { name: /^general$/i })
  await generalBtn.waitFor({ timeout: 15000 })
  await generalBtn.click({ force: true })
  await page.waitForTimeout(2000)

  const scrollContainer = page
    .locator("[data-room-message-id]")
    .first()
    .locator("xpath=ancestor::div[contains(@class,'overflow-y-auto')][1]")
  await scrollContainer.waitFor({ timeout: 15000 })

  scrollMetrics = await scrollContainer.evaluate((el) => {
    const max = el.scrollHeight - el.clientHeight
    el.scrollTop = Math.round(max / 2)
    el.dispatchEvent(new Event("scroll", { bubbles: true }))
    return {
      scrollTop: el.scrollTop,
      scrollHeight: el.scrollHeight,
      clientHeight: el.clientHeight,
      maxScroll: max,
    }
  })
  console.log("scrolled halfway", scrollMetrics)

  await page.waitForTimeout(400)

  const lsAfterScroll = await page.evaluate(() =>
    window.localStorage.getItem("trade-room-scroll-positions-v1")
  )
  console.log("localStorage after scroll", lsAfterScroll)

  const offTopicBtn = page
    .locator(".hidden.md\\:flex")
    .getByRole("button", { name: /^off-topic$/i })
  await offTopicBtn.click({ force: true })
  await page.waitForTimeout(800)

  const announcementsBtn = page
    .locator(".hidden.md\\:flex")
    .getByRole("button", { name: /^announcements$/i })
  await announcementsBtn.click({ force: true })
  await page.waitForTimeout(800)

  await offTopicBtn.click({ force: true })
  await page.waitForTimeout(800)

  const lsBeforeReturn = await page.evaluate(() =>
    window.localStorage.getItem("trade-room-scroll-positions-v1")
  )
  console.log("localStorage before return to general", lsBeforeReturn)

  await announcementsBtn.click({ force: true })
  await page.waitForTimeout(1500)

  await generalBtn.click({ force: true })
  await page.waitForTimeout(2000)

  finalMetrics = await scrollContainer.evaluate((el) => ({
    scrollTop: el.scrollTop,
    scrollHeight: el.scrollHeight,
    clientHeight: el.clientHeight,
  }))

  localStoragePayload = await page.evaluate(() =>
    window.localStorage.getItem("trade-room-scroll-positions-v1")
  )
} finally {
  await supabase.from("rooms").delete().eq("id", room.id)
  await supabase.auth.admin.deleteUser(userId)
  if (browser) await browser.close()
}

const parsedLogs = verifyLogs.map((line) => {
  try {
    const jsonStart = line.indexOf("{")
    if (jsonStart === -1) return { line }
    return { tag: line.slice(0, jsonStart).trim(), ...JSON.parse(line.slice(jsonStart)) }
  } catch {
    return { line }
  }
})

const result = {
  scrollMetrics,
  finalMetrics,
  localStoragePayload: localStoragePayload
    ? JSON.parse(localStoragePayload)
    : null,
  verifyLogCount: verifyLogs.length,
  verifyLogs: parsedLogs,
}

console.log(JSON.stringify(result, null, 2))
process.exit(0)
