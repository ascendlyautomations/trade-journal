/**
 * Browser E2E trace — failure scenario matrix for /messages inbox.
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
const supabaseUrl = env.NEXT_PUBLIC_SUPABASE_URL
const serviceKey = env.SUPABASE_SERVICE_ROLE_KEY
const anonKey = env.NEXT_PUBLIC_SUPABASE_ANON_KEY
const projectRef = new URL(supabaseUrl).hostname.split(".")[0]
const storageKey = `sb-${projectRef}-auth-token`

const admin = createClient(supabaseUrl, serviceKey, {
  auth: { autoRefreshToken: false, persistSession: false },
})
const anon = createClient(supabaseUrl, anonKey, {
  auth: { autoRefreshToken: false, persistSession: false },
})

async function buildSessionForEmail(email) {
  const { data: link } = await admin.auth.admin.generateLink({
    type: "magiclink",
    email,
  })
  const { data: sessionData } = await anon.auth.verifyOtp({
    type: "magiclink",
    token_hash: link.properties.hashed_token,
  })
  const session = sessionData.session
  return JSON.stringify({
    access_token: session.access_token,
    refresh_token: session.refresh_token,
    expires_at: session.expires_at,
    expires_in: session.expires_in,
    token_type: session.token_type,
    user: session.user,
  })
}

async function runScenario(name, setup) {
  const browser = await chromium.launch({ headless: true })
  const context = await browser.newContext({ viewport: { width: 1280, height: 900 } })
  const page = await context.newPage()
  const traceLogs = []
  page.on("console", (msg) => {
    const text = msg.text()
    if (text.includes("[messages-inbox-trace]")) traceLogs.push(text)
  })

  await setup(page, context)

  await page.goto("http://localhost:3000/messages", { waitUntil: "networkidle" })
  await page.waitForTimeout(4000)

  const emptyVisible = await page
    .getByText("No Conversations Yet")
    .isVisible()
    .catch(() => false)
  const listVisible = await page
    .locator('[aria-label="Conversation options"]')
    .first()
    .isVisible()
    .catch(() => false)

  const pick = (prefix) =>
    traceLogs.find((l) => l.includes(prefix)) ?? "(missing)"

  console.log(`\n========== ${name} ==========`)
  console.log("UI emptyState:", emptyVisible, "list:", listVisible)
  console.log("step:1-auth:", pick("step:1-auth"))
  console.log("step:2-participants:", pick("step:2-participants"))
  console.log("step:2-failed:", pick("step:2-participants:failed"))
  console.log("step:1-failed:", pick("step:1-auth:failed"))
  console.log("step:5:", pick("step:5-before-setState"))
  console.log("step:6:", pick("step:6-after-render"))

  await browser.close()
}

await runScenario("A: no auth session", async (page) => {
  await page.goto("http://localhost:3000/login")
  await page.evaluate(() => {
    localStorage.clear()
    sessionStorage.clear()
  })
})

await runScenario("B: valid session (tradetraxs@gmail.com)", async (page) => {
  const value = await buildSessionForEmail("tradetraxs@gmail.com")
  await page.goto("http://localhost:3000/login")
  await page.evaluate(
    ({ key, value }) => localStorage.setItem(key, value),
    { key: storageKey, value }
  )
})

await runScenario("C: demo mode flag, no auth", async (page) => {
  await page.goto("http://localhost:3000/login")
  await page.evaluate(() => {
    localStorage.clear()
    sessionStorage.setItem("tradetraxs_demo_mode", "1")
  })
})

await runScenario("D: demo mode + valid real session", async (page) => {
  const value = await buildSessionForEmail("tradetraxs@gmail.com")
  await page.goto("http://localhost:3000/login")
  await page.evaluate(
    ({ key, value }) => {
      sessionStorage.setItem("tradetraxs_demo_mode", "1")
      localStorage.setItem(key, value)
    },
    { key: storageKey, value }
  )
})

await runScenario("E: auth user in context but session cleared before fetch", async (page) => {
  const value = await buildSessionForEmail("tradetraxs@gmail.com")
  await page.goto("http://localhost:3000/login")
  await page.evaluate(
    ({ key, value }) => localStorage.setItem(key, value),
    { key: storageKey, value }
  )
  await page.goto("http://localhost:3000/dashboard", { waitUntil: "networkidle" })
  await page.waitForTimeout(1500)
  await page.evaluate((key) => localStorage.removeItem(key), storageKey)
})
