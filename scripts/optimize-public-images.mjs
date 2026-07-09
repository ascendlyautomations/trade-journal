/**
 * One-time optimizer for large public PNG/JPG assets.
 * Run: node scripts/optimize-public-images.mjs
 */
import fs from "node:fs"
import path from "node:path"
import sharp from "sharp"

const root = path.resolve(process.cwd(), "public")

const targets = [
  "tradetrax-bg.png",
  "images/hero-bg.png",
  "images/Trading_Journal.png",
  "images/AI_Trade_Analyst.png",
  "images/Trader_Profiles.png",
  "images/public-profiles.png",
  "images/dashboard.png",
  "images/trade-input.png",
  "images/Trade_Rooms.png",
  "images/messaging-ui-v2.png",
  "images/Trading_Reels.png",
  "images/community-learning.png",
  "images/trade-history.png",
  "images/Know_Your_Edge.png",
  "images/social-feed.png",
  "images/leaderboard.png",
  "images/Prop_Firm_Mode.png",
]

async function convertOne(relativePath) {
  const input = path.join(root, relativePath)
  if (!fs.existsSync(input)) {
    console.warn("skip missing:", relativePath)
    return
  }
  const webpPath = input.replace(/\.(png|jpe?g)$/i, ".webp")
  const before = fs.statSync(input).size
  await sharp(input)
    .webp({ quality: 82, effort: 4 })
    .toFile(webpPath)
  const after = fs.statSync(webpPath).size
  const pct = Math.round((1 - after / before) * 100)
  console.log(`${relativePath} → ${path.basename(webpPath)} (${Math.round(before / 1024)}KB → ${Math.round(after / 1024)}KB, -${pct}%)`)
}

for (const rel of targets) {
  await convertOne(rel)
}

const unusedHero = path.join(root, "hero.png")
if (fs.existsSync(unusedHero)) {
  fs.unlinkSync(unusedHero)
  console.log("removed unused public/hero.png")
}
