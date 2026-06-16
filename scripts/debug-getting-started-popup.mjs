/**
 * Browser debug script for Getting Started popups.
 * Usage: npx playwright install chromium && node scripts/debug-getting-started-popup.mjs
 */
import { chromium } from "playwright"

const BASE = process.env.BASE_URL ?? "http://localhost:3000"

async function main() {
  const browser = await chromium.launch({ headless: false })
  const context = await browser.newContext()
  const page = await context.newPage()

  const logs = []
  page.on("console", (msg) => {
    const text = msg.text()
    if (text.includes("[getting-started]")) {
      logs.push(text)
      console.log(text)
    }
  })

  await page.goto(`${BASE}/dashboard`, { waitUntil: "domcontentloaded" })
  await page.waitForTimeout(3000)

  const url = page.url()
  if (url.includes("/login")) {
    console.log("NOT_LOGGED_IN: open browser, log in, log a trade, watch [getting-started] logs")
    await page.waitForTimeout(120000)
    await browser.close()
    return
  }

  await page.evaluate(() => {
    localStorage.setItem("DEBUG_GETTING_STARTED", "1")
  })

  console.log("Logged in. Checking for Getting Started modal in DOM...")
  const modalBefore = await page.locator('text=Getting Started Progress').count()
  console.log("Getting Started Progress modals before action:", modalBefore)

  const addTrade = page.getByRole("link", { name: /add trade/i }).first()
  if (await addTrade.count()) {
    console.log("Navigate to add trade...")
    await addTrade.click()
    await page.waitForTimeout(2000)
  }

  console.log("Waiting 60s for manual trade save — watch console for [getting-started] logs...")
  await page.waitForTimeout(60000)

  const modalAfter = await page.locator('text=Getting Started Progress').count()
  console.log("Getting Started Progress modals after:", modalAfter)
  console.log("Captured logs:", logs.length)

  await browser.close()
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
