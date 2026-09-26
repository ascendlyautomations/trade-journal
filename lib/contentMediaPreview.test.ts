import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import test from "node:test"
import { fileURLToPath } from "node:url"

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")

function source(relative: string): string {
  return fs.readFileSync(path.join(ROOT, relative), "utf8")
}

test("desktop content previews cap height without a global img rule", () => {
  const css = source("app/components/contentMediaPreview.css")
  assert.match(css, /max-height:\s*520px/)
  assert.match(css, /@media \(min-width: 768px\)/)
  assert.match(css, /min\(70dvh, 680px\)/)
  assert.equal(css.includes("img {"), false)
  assert.equal(css.includes("img{"), false)
})

test("card previews preserve aspect and do not force full width", () => {
  const component = source("app/components/ContentMediaPreview.tsx")
  assert.match(component, /w-auto max-w-full object-contain/)
  assert.match(component, /object-cover/)
  assert.match(component, /resolveTradeScreenshotDisplayMode/)
  assert.equal(component.includes("aspect-[4/3]"), false)
  assert.equal(component.includes("w-full h-auto"), false)
})

test("feed previews contain the complete image inside a height cap", () => {
  const component = source("app/components/ContentMediaPreview.tsx")
  const css = source("app/components/contentMediaPreview.css")
  const feed = source("app/components/feed/FeedPostScreenshot.tsx")
  assert.match(component, /context\?: "card" \| "detail" \| "feed"/)
  assert.match(component, /resolvedContext === "feed"/)
  assert.match(component, /tt-content-media-preview--feed[\s\S]*object-contain/)
  assert.equal(component.includes("setFeedLandscape"), false)
  assert.equal(component.includes("naturalWidth"), false)
  assert.match(css, /\.tt-content-media-preview--feed[\s\S]*object-fit:\s*contain/)
  assert.match(css, /\.tt-content-media-preview--feed\s*\{[^}]*max-height:\s*540px/)
  assert.equal(css.includes("aspect-ratio: 4 / 3"), false)
  assert.equal(css.includes("object-fit: cover"), false)
  assert.match(feed, /context="feed"/)
  assert.match(feed, /preset="feed-card"/)
  assert.match(component, /preset="feed-card"/)
  assert.match(
    source("app/components/AchievementCard.tsx"),
    /mediaContext === "feed"\s*\?\s*"feed-card"/
  )
  assert.match(source("app/components/ui/DetailModalImage.tsx"), /variant="detail"/)
  assert.equal(
    source("app/components/ui/DetailModalImage.tsx").includes('context="feed"'),
    false
  )
  assert.match(
    source("app/components/feed/FeedAchievementPostCard.tsx"),
    /mediaContext="feed"/
  )
  assert.equal(
    source("app/achievements/page.tsx").includes('mediaContext="feed"'),
    false
  )
  assert.match(source("app/achievements/page.tsx"), /gallery/)
  assert.match(
    source("app/components/AchievementCard.tsx"),
    /gallery\s*\?\s*"achievement-card"/
  )
  assert.equal(
    source("app/components/profile/ProfileAchievementsTab.tsx").includes("gallery"),
    false
  )
  assert.equal(
    source("app/components/feed/FeedAchievementPostCard.tsx").includes("gallery"),
    false
  )
})

test("social card surfaces use the shared preview", () => {
  const surfaces = [
    "app/components/feed/FeedPostScreenshot.tsx",
    "app/components/profile/ProfilePostCard.tsx",
    "app/components/profile/ProfileTradeCard.tsx",
    "app/components/TradeCard.tsx",
    "app/components/ui/TradeScreenshotPreview.tsx",
    "app/components/AchievementCard.tsx",
    "app/trade/[id]/TradeDetailPageClient.tsx",
    "app/components/ui/DetailModalImage.tsx",
  ]
  for (const relative of surfaces) {
    assert.match(source(relative), /ContentMediaPreview/, relative)
  }
})

test("message screenshots stay on the previous renderer", () => {
  const messages = source("app/(app)/messages/[id]/page.tsx")
  assert.match(messages, /FeedPostScreenshot/)
  assert.equal(messages.includes("ContentMediaPreview"), false)
  const screenshot = source("app/components/feed/FeedPostScreenshot.tsx")
  assert.match(screenshot, /variant === "message"/)
  assert.match(screenshot, /TradeScreenshotImage/)
})
