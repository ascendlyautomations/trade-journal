/**
 * Reproduce empty inbox — focus on step 2 zero_rows vs step 1 skip.
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

async function runScenario(name, setup) {
  const browser = await chromium.launch({ headless: true })
  const page = await browser.newPage()
  const traceLogs = []
  page.on("console", (msg) => {
    const text = msg.text()
    if (text.includes("[messages-inbox-trace]")) traceLogs.push(text)
  })

  await page.goto("http://localhost:3000/login")
  await setup(page)
  await page.goto("http://localhost:3000/messages", { waitUntil: "networkidle" })
  await page.waitForTimeout(5000)

  const emptyVisible = await page
    .getByText("No Conversations Yet")
    .isVisible()
    .catch(() => false)
  const skeletonVisible = await page
    .locator('[aria-label="Loading conversations"]')
    .isVisible()
    .catch(() => false)
  const listVisible = await page
    .locator('[aria-label="Conversation options"]')
    .first()
    .isVisible()
    .catch(() => false)

  const last = (needle) => {
    const hits = traceLogs.filter((l) => l.includes(needle))
    return hits[hits.length - 1] ?? "(missing)"
  }

  console.log(`\n===== ${name} =====`)
  console.log({ emptyVisible, skeletonVisible, listVisible })
  console.log("last step:1-auth:", last("step:1-auth"))
  console.log("last step:1-failed:", last("step:1-auth:failed"))
  console.log("last step:2:", last("step:2-participants"))
  console.log("last step:2-failed:", last("step:2-participants:failed"))
  console.log("last step:5:", last("step:5-before-setState"))
  console.log("last step:6:", last("step:6-after-render"))

  await browser.close()
}

// F: Valid session JSON but invalid access_token (simulates corrupt/expired storage)
await runScenario("F: corrupt access_token in localStorage", async (page) => {
  await page.evaluate((key) => {
    localStorage.setItem(
      key,
      JSON.stringify({
        access_token: "invalid.jwt.token",
        refresh_token: "invalid",
        expires_at: Math.floor(Date.now() / 1000) - 3600,
        expires_in: 3600,
        token_type: "bearer",
        user: {
          id: "de0ad507-4cb4-4c09-a5eb-46536567e2c3",
          email: "tradetraxs@gmail.com",
        },
      })
    )
  }, storageKey)
})

// G: User object in storage but empty tokens
await runScenario("G: user in storage, no tokens", async (page) => {
  await page.evaluate((key) => {
    localStorage.setItem(
      key,
      JSON.stringify({
        access_token: "",
        refresh_token: "",
        user: {
          id: "de0ad507-4cb4-4c09-a5eb-46536567e2c3",
          email: "tradetraxs@gmail.com",
        },
      })
    )
  }, storageKey)
})

// H: Login form flow (password user with conversations)
const email = "auditfree@gmail.com"
const password = "InboxTraceTest123!"
const { data: existing } = await admin.auth.admin.listUsers({ perPage: 1000 })
const existingUser = existing?.users?.find((u) => u.email === email)
if (existingUser) {
  await admin.auth.admin.updateUserById(existingUser.id, { password })
} else {
  await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  })
}

await runScenario("H: login form then /messages", async (page) => {
  await page.evaluate(() => {
    localStorage.clear()
    sessionStorage.clear()
  })
  await page.getByPlaceholder("Email").fill(email)
  await page.getByPlaceholder("Password").fill(password)
  await page.locator("form").getByRole("button", { name: /^Login$/i }).click()
  await page.waitForURL(/dashboard|app|messages|trades/, { timeout: 45000 })
  await page.waitForTimeout(2000)
})

// J: cold direct /messages (session via addInitScript, no /login first)
{
  const email = "tradetraxs@gmail.com"
  const { data: link } = await admin.auth.admin.generateLink({
    type: "magiclink",
    email,
  })
  const anon = createClient(supabaseUrl, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  })
  const { data: sd } = await anon.auth.verifyOtp({
    type: "magiclink",
    token_hash: link.properties.hashed_token,
  })
  const session = sd.session
  const value = JSON.stringify({
    access_token: session.access_token,
    refresh_token: session.refresh_token,
    expires_at: session.expires_at,
    expires_in: session.expires_in,
    token_type: session.token_type,
    user: session.user,
  })

  const browser = await chromium.launch({ headless: true })
  const context = await browser.newContext()
  await context.addInitScript(
    ({ key, value }) => localStorage.setItem(key, value),
    { key: storageKey, value }
  )
  const page = await context.newPage()
  const traceLogs = []
  page.on("console", (msg) => {
    const text = msg.text()
    if (text.includes("[messages-inbox-trace]")) traceLogs.push(text)
  })
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
  const last = (needle) => {
    const hits = traceLogs.filter((l) => l.includes(needle))
    return hits[hits.length - 1] ?? "(missing)"
  }
  console.log("\n===== J: cold direct /messages =====")
  console.log({ emptyVisible, listVisible })
  console.log("last step:1-auth:", last("step:1-auth"))
  console.log("last step:1-failed:", last("step:1-auth:failed"))
  console.log("last step:2:", last("step:2-participants"))
  console.log("last step:2-failed:", last("step:2-participants:failed"))
  console.log("last step:5:", last("step:5-before-setState"))
  console.log("last step:6:", last("step:6-after-render"))
  await browser.close()
}

