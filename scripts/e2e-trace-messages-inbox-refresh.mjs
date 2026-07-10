/**
 * Scenario I: successful load then session cleared + focus refresh (stale overwrite).
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

const email = "tradetraxs@gmail.com"
const { data: link } = await admin.auth.admin.generateLink({
  type: "magiclink",
  email,
})
const { data: sessionData } = await anon.auth.verifyOtp({
  type: "magiclink",
  token_hash: link.properties.hashed_token,
})
const session = sessionData.session
const storageValue = JSON.stringify({
  access_token: session.access_token,
  refresh_token: session.refresh_token,
  expires_at: session.expires_at,
  expires_in: session.expires_in,
  token_type: session.token_type,
  user: session.user,
})

const browser = await chromium.launch({ headless: true })
const page = await browser.newPage()
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
  ({ key, value }) => localStorage.setItem(key, value),
  { key: storageKey, value: storageValue }
)
await page.goto("http://localhost:3000/messages", { waitUntil: "networkidle" })
await page.waitForTimeout(3000)

console.log("\n--- after initial load ---")
console.log("list visible:", await page.locator('[aria-label="Conversation options"]').first().isVisible().catch(() => false))

await page.evaluate((key) => localStorage.removeItem(key), storageKey)
await page.evaluate(() => window.dispatchEvent(new Event("focus")))
await page.waitForTimeout(3000)

const emptyVisible = await page.getByText("No Conversations Yet").isVisible().catch(() => false)
const listVisible = await page.locator('[aria-label="Conversation options"]').first().isVisible().catch(() => false)

const refreshLogs = traceLogs.filter((l) => l.includes("refresh"))
console.log("\n--- after session cleared + focus refresh ---")
console.log({ emptyVisible, listVisible })
console.log("refresh fetches:", refreshLogs.length)
console.log("last refresh step:2:", refreshLogs.filter((l) => l.includes("step:2")).pop())
console.log("last step:6:", traceLogs.filter((l) => l.includes("step:6")).pop())

await browser.close()
