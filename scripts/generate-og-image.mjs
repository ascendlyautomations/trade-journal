/**
 * Generate public/og-image.png (1200×630) for Open Graph / Twitter cards.
 * Uses the branded background only — do not composite a second logo (the
 * background already includes the TradeTraxs mark).
 * Run: node scripts/generate-og-image.mjs
 */
import fs from "node:fs"
import path from "node:path"
import sharp from "sharp"

const root = path.resolve(process.cwd(), "public")
const out = path.join(root, "og-image.png")
const bgWebp = path.join(root, "tradetrax-bg.webp")
const bgPng = path.join(root, "tradetrax-bg.png")

const WIDTH = 1200
const HEIGHT = 630

async function main() {
  const bg = fs.existsSync(bgWebp)
    ? bgWebp
    : fs.existsSync(bgPng)
      ? bgPng
      : null
  if (!bg) {
    throw new Error("Missing tradetrax-bg.webp (or tradetrax-bg.png)")
  }

  await sharp(bg)
    .resize(WIDTH, HEIGHT, { fit: "cover", position: "center" })
    .png({ compressionLevel: 9 })
    .toFile(out)

  const size = fs.statSync(out).size
  console.log(`Wrote ${out} (${Math.round(size / 1024)} KB, ${WIDTH}×${HEIGHT})`)
}

await main()
