import { chromium } from "playwright"

const BASE = process.env.BASE_URL ?? "http://localhost:3000"

const browser = await chromium.launch({ headless: true })
const page = await browser.newPage()
const logs = []

page.on("console", (msg) => {
  const text = msg.text()
  if (text.includes("[getting-started]")) logs.push(text)
})

await page.goto(`${BASE}/dashboard`, { waitUntil: "networkidle", timeout: 30000 })
await page.waitForTimeout(8000)

const url = page.url()
const bodyText = await page.locator("body").innerText()
const hasChecklist = bodyText.includes("Getting Started")
const hasLogin = bodyText.includes("Sign in") || url.includes("/login")

console.log(JSON.stringify({
  url,
  hasLogin,
  hasChecklist,
  logCount: logs.length,
  logs,
}, null, 2))

await browser.close()
