/**
 * Generate public/og-image.png (1200×630) for Open Graph / Twitter cards.
 * Run: node scripts/generate-og-image.mjs
 */
import fs from "node:fs"
import path from "node:path"
import sharp from "sharp"

const root = path.resolve(process.cwd(), "public")
const out = path.join(root, "og-image.png")
const bg = path.join(root, "tradetrax-bg.webp")
const logo = path.join(root, "logo.png")

const WIDTH = 1200
const HEIGHT = 630

async function main() {
  if (!fs.existsSync(bg)) {
    throw new Error("Missing tradetrax-bg.webp")
  }
  if (!fs.existsSync(logo)) {
    throw new Error("Missing logo.png")
  }

  const background = await sharp(bg)
    .resize(WIDTH, HEIGHT, { fit: "cover", position: "center" })
    .modulate({ brightness: 0.55 })
    .toBuffer()

  const logoBuffer = await sharp(logo)
    .resize(280, 280, { fit: "inside", withoutEnlargement: true })
    .png()
    .toBuffer()

  const logoMeta = await sharp(logoBuffer).metadata()
  const logoW = logoMeta.width ?? 280
  const logoH = logoMeta.height ?? 280

  const titleSvg = `
    <svg width="${WIDTH}" height="${HEIGHT}">
      <style>
        .title { fill: #93c5fd; font-size: 52px; font-family: Arial, Helvetica, sans-serif; font-weight: 700; }
        .subtitle { fill: #e2e8f0; font-size: 28px; font-family: Arial, Helvetica, sans-serif; font-weight: 400; }
      </style>
      <text x="600" y="420" text-anchor="middle" class="title">TradeTraxs</text>
      <text x="600" y="470" text-anchor="middle" class="subtitle">AI Trading Journal &amp; Analytics</text>
    </svg>
  `

  await sharp(background)
    .composite([
      {
        input: logoBuffer,
        top: Math.round(HEIGHT / 2 - logoH / 2 - 60),
        left: Math.round(WIDTH / 2 - logoW / 2),
      },
      { input: Buffer.from(titleSvg), top: 0, left: 0 },
    ])
    .png({ compressionLevel: 9 })
    .toFile(out)

  const size = fs.statSync(out).size
  console.log(`Wrote ${out} (${Math.round(size / 1024)} KB, ${WIDTH}×${HEIGHT})`)
}

await main()
