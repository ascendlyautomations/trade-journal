/**
 * Browser E2E trace for /messages inbox pipeline.
 * Run: node scripts/e2e-trace-messages-inbox.mjs
 * Requires: npm run start (or dev) on :3000
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

const admin = createClient(supabaseUrl, serviceKey, {
  auth: { autoRefreshToken: false, persistSession: false },
})
const anon = createClient(supabaseUrl, anonKey, {
  auth: { autoRefreshToken: false, persistSession: false },
})

const targetEmail = "tradetraxs@gmail.com"

const { data: usersData } = await admin.auth.admin.listUsers({ perPage: 1000 })
const targetUser = usersData?.users?.find((u) => u.email === targetEmail)
if (!targetUser) {
  console.error("Target user not found:", targetEmail)
  process.exit(1)
}

const { data: link, error: linkErr } = await admin.auth.admin.generateLink({
  type: "magiclink",
  email: targetEmail,
})
if (linkErr || !link?.properties?.hashed_token) {
  console.error("magic link failed", linkErr)
  process.exit(1)
}

const { data: sessionData, error: otpErr } = await anon.auth.verifyOtp({
  type: "magiclink",
  token_hash: link.properties.hashed_token,
})
if (otpErr || !sessionData.session) {
  console.error("verifyOtp failed", otpErr)
  process.exit(1)
}

const session = sessionData.session
const projectRef = new URL(supabaseUrl).hostname.split(".")[0]
const storageKey = `sb-${projectRef}-auth-token`
const storageValue = JSON.stringify({
  access_token: session.access_token,
  refresh_token: session.refresh_token,
  expires_at: session.expires_at,
  expires_in: session.expires_in,
  token_type: session.token_type,
  user: session.user,
})

const browser = await chromium.launch({ headless: true })
const context = await browser.newContext({ viewport: { width: 1280, height: 900 } })
const page = await context.newPage()

const traceLogs = []
page.on("console", (msg) => {
  const text = msg.text()
  if (text.includes("[messages-inbox-trace]")) {
    traceLogs.push(text)
    console.log(text)
  }
})

await page.goto("http://localhost:3000/login")
await page.evaluate(
  ({ key, value }) => {
    localStorage.setItem(key, value)
  },
  { key: storageKey, value: storageValue }
)

await page.goto("http://localhost:3000/messages", { waitUntil: "networkidle" })
await page.waitForTimeout(5000)

const emptyVisible = await page
  .getByText("No Conversations Yet")
  .isVisible()
  .catch(() => false)
const listVisible = await page
  .locator('[aria-label="Conversation options"]')
  .first()
  .isVisible()
  .catch(() => false)

console.log("\n=== BROWSER UI ===")
console.log("emptyStateVisible:", emptyVisible)
console.log("conversationListVisible:", listVisible)

console.log("\n=== TRACE SUMMARY ===")
for (const line of traceLogs) {
  console.log(line)
}

await browser.close()
