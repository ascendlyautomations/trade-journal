/**
 * Capture Instagram marketing ads (1080×1350) from /marketing/* routes.
 *
 * Usage:
 *   1. Start the app: npm run dev
 *   2. npm run export:marketing-ads
 *
 * Optional: BASE_URL=http://localhost:3000 npm run export:marketing-ads
 */
import { chromium } from "playwright"
import { mkdirSync } from "node:fs"
import { resolve } from "node:path"

const BASE_URL = (process.env.BASE_URL || "http://localhost:3000").replace(
  /\/$/,
  ""
)
const OUT_DIR = resolve(process.cwd(), "public", "marketing-exports")
const VIEWPORT = { width: 1080, height: 1350 }

const ADS = [
  { path: "/marketing/dashboard", file: "dashboard.png" },
  { path: "/marketing/prop-firm", file: "prop-firm.png" },
  { path: "/marketing/ai-analyst", file: "ai-analyst.png" },
  { path: "/marketing/trading-clips", file: "trading-clips.png" },
  { path: "/marketing/community-feed", file: "community-feed.png" },
  { path: "/marketing/advanced-insights", file: "advanced-insights.png" },
]

mkdirSync(OUT_DIR, { recursive: true })

const browser = await chromium.launch({ headless: true })
const context = await browser.newContext({
  viewport: VIEWPORT,
  deviceScaleFactor: 1,
})
const page = await context.newPage()

// Belt-and-suspenders: never show cookie chrome on ad captures
await page.addInitScript(() => {
  try {
    localStorage.setItem(
      "tradetraxs_cookie_consent_v1",
      JSON.stringify({
        version: 1,
        choice: "essential",
        essential: true,
        analytics: false,
        updatedAt: new Date().toISOString(),
      })
    )
  } catch {
    /* ignore */
  }
})

for (const ad of ADS) {
  const url = `${BASE_URL}${ad.path}`
  console.log(`Capturing ${ad.file} ← ${url}`)
  await page.goto(url, { waitUntil: "networkidle", timeout: 90_000 })

  await page.waitForFunction(
    () => document.fonts?.status === "loaded" || document.fonts?.status == null,
    { timeout: 30_000 }
  ).catch(() => {})

  await page.waitForSelector('[data-marketing-ready="true"]', {
    timeout: 60_000,
  })

  // Hide Next.js / tooling chrome that can leak into captures
  await page.addStyleTag({
    content: `
      nextjs-portal,
      [data-next-badge],
      [data-next-mark],
      #__next-build-watcher,
      [data-nextjs-toast],
      [data-nextjs-dialog-overlay] {
        display: none !important;
        visibility: hidden !important;
        opacity: 0 !important;
        pointer-events: none !important;
      }
    `,
  })

  // Extra settle for Recharts SVG paint + images
  await page.waitForTimeout(800)

  const frame = page.locator("[data-marketing-ad]")
  await frame.waitFor({ state: "visible", timeout: 30_000 })
  await frame.screenshot({
    path: resolve(OUT_DIR, ad.file),
    type: "png",
  })
  console.log(`  saved ${ad.file}`)
}

await browser.close()
console.log(`\nDone. Exports in ${OUT_DIR}`)
