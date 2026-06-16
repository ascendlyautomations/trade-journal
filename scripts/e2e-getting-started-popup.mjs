/**
 * E2E: create temp user + account, log first trade, assert Getting Started popup.
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

const email = `gs-popup-${Date.now()}@tradetraxs-test.invalid`
const password = "TestPopupPass123!"
const username = `gst${String(Date.now()).slice(-8)}`

const { data: created, error: createErr } = await supabase.auth.admin.createUser({
  email,
  password,
  email_confirm: true,
})
if (createErr) throw createErr

const userId = created.user.id
console.log("created user", userId)

await supabase.from("profiles").upsert({
  id: userId,
  username,
  onboarding_completed: true,
})

const { data: account, error: acctErr } = await supabase
  .from("accounts")
  .insert({
    user_id: userId,
    name: "E2E Test",
    account_size: "50000",
    account_number: "E2E001",
    category: "Personal",
    mode: "Live",
    is_active: true,
  })
  .select("id")
  .single()
if (acctErr) throw acctErr

const browser = await chromium.launch({ headless: true })
const context = await browser.newContext({ viewport: { width: 1280, height: 900 } })
const page = await context.newPage()
const logs = []
page.on("console", (msg) => {
  const text = msg.text()
  if (text.includes("[getting-started]")) logs.push(text)
})

await page.goto("http://localhost:3000/login")
await page.getByPlaceholder("Email").fill(email)
await page.getByPlaceholder("Password").fill(password)
await page.locator("form").getByRole("button", { name: /^Login$/i }).click()
await page.waitForURL(/dashboard|app/, { timeout: 45000 })
await page.waitForTimeout(2000)

await page.evaluate((uid) => {
  for (const k of Object.keys(localStorage)) {
    if (k.includes("getting_started")) localStorage.removeItem(k)
  }
}, userId)

await page.goto("http://localhost:3000/app")
await page.waitForTimeout(3000)

await page.locator(".hidden.md\\:flex .account-dropdown").click()
await page.locator(".hidden.md\\:flex .account-dropdown").getByText("E2E Test").click()
await page.getByPlaceholder("e.g. MNQ, ES, AAPL").fill("ES")
await page.locator('label:has-text("P&L")').locator("..").locator("input").fill("100")
await page.getByRole("button", { name: /^Add Trade$/i }).click()
await page.waitForTimeout(6000)

const gsModal = await page.locator('text=Getting Started Progress').count()
const gsBody = await page.locator('text=Log your first trade').count()

const result = { gsModal, gsBody, logCount: logs.length, logs, pass: gsModal > 0 && gsBody > 0 }
console.log(JSON.stringify(result, null, 2))

await page.screenshot({ path: "scripts/e2e-getting-started-popup.png", fullPage: true })

await supabase.auth.admin.deleteUser(userId)
await browser.close()

process.exit(result.pass ? 0 : 1)
