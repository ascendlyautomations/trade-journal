import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import test from "node:test"
import { fileURLToPath } from "node:url"
import { DEFAULT_CONTENT_COVER_TRANSFORM } from "./contentImageV2.ts"
import {
  ATTACHMENT_JPEG_QUALITY,
  ATTACHMENT_MAX_EDGE,
  AVATAR_JPEG_QUALITY,
  AVATAR_OUTPUT_SIZE,
  CHAT_JPEG_QUALITY,
  CHAT_MAX_EDGE,
  STORY_JPEG_QUALITY,
  STORY_OUTPUT_HEIGHT,
  STORY_OUTPUT_WIDTH,
  planBoundedOriginal,
  planFixedCover,
  semanticJpegFileName,
} from "./semanticImage.ts"

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")

function source(relative: string): string {
  return fs.readFileSync(path.join(ROOT, relative), "utf8")
}

test("avatar and room covers are square 512 JPEGs", () => {
  const plan = planFixedCover(4032, 3024, "avatar", DEFAULT_CONTENT_COVER_TRANSFORM)
  assert.equal(plan.output.width, AVATAR_OUTPUT_SIZE)
  assert.equal(plan.output.height, AVATAR_OUTPUT_SIZE)
  assert.equal(plan.output.quality, AVATAR_JPEG_QUALITY)
  assert.ok(plan.crop.width > 0)
  assert.ok(plan.crop.height > 0)
  assert.ok(plan.crop.x >= 0)
  assert.ok(plan.crop.y >= 0)
  assert.ok(plan.crop.x + plan.crop.width <= 4032 + 0.01)
  assert.ok(plan.crop.y + plan.crop.height <= 3024 + 0.01)
  assert.ok(Math.abs(plan.crop.width - plan.crop.height) < 1)
})

test("story cover is 1080x1920 and bakes the pan into the crop", () => {
  const identity = planFixedCover(1080, 1920, "story", DEFAULT_CONTENT_COVER_TRANSFORM)
  assert.equal(identity.output.width, STORY_OUTPUT_WIDTH)
  assert.equal(identity.output.height, STORY_OUTPUT_HEIGHT)
  assert.equal(identity.output.quality, STORY_JPEG_QUALITY)
  assert.equal(STORY_OUTPUT_WIDTH / STORY_OUTPUT_HEIGHT, 9 / 16)

  const shifted = planFixedCover(4000, 3000, "story", {
    zoom: 2,
    offset: { x: 80, y: -40 },
  })
  const centered = planFixedCover(4000, 3000, "story", {
    zoom: 2,
    offset: { x: 0, y: 0 },
  })
  assert.notEqual(shifted.crop.x, centered.crop.x)
  assert.equal(shifted.output.width, 1080)
  assert.equal(shifted.output.height, 1920)
})

test("chat and attachments keep aspect, cap at 2560, and do not upscale", () => {
  const large = planBoundedOriginal(4032, 3024, CHAT_MAX_EDGE)
  assert.ok(Math.max(large.width, large.height) <= 2560)
  assert.ok(Math.abs(large.width / large.height - 4032 / 3024) < 0.01)
  assert.ok(large.scale < 1)

  const small = planBoundedOriginal(800, 600, ATTACHMENT_MAX_EDGE)
  assert.equal(small.width, 800)
  assert.equal(small.height, 600)
  assert.equal(small.scale, 1)
  assert.equal(CHAT_MAX_EDGE, ATTACHMENT_MAX_EDGE)
  assert.equal(CHAT_JPEG_QUALITY, 0.82)
  assert.equal(ATTACHMENT_JPEG_QUALITY, 0.82)
  assert.equal(semanticJpegFileName("Screen.PNG"), "Screen.jpg")
})

test("semantic renderer encodes once and does not call the legacy compressors", () => {
  const renderer = source("lib/renderSemanticImage.ts")
  assert.equal(renderer.split("toBlob").length - 1, 1)
  assert.equal(renderer.includes("compressImage"), false)
  assert.equal(renderer.includes("compressScreenshot"), false)
  assert.match(renderer, /imageOrientation: "from-image"/)
})

test("migrated surfaces prepare once and do not force the social content crop", () => {
  const cases: Array<[string, string]> = [
    ["app/settings/page.tsx", "avatar"],
    ["app/components/ProfileOnboarding.tsx", "avatar"],
    ["app/(app)/messages/[id]/page.tsx", "chat"],
    ["app/community/page.tsx", "chat"],
    ["app/chat/page.tsx", "chat"],
    ["app/feedback/page.tsx", "attachment"],
    ["app/support/page.tsx", "attachment"],
    ["app/suggestions/page.tsx", "attachment"],
    ["lib/bugReports.ts", "attachment"],
    ["app/(app)/feed/page.tsx", "story"],
    ["app/profile/[id]/page.tsx", "story"],
  ]

  for (const [relative, kind] of cases) {
    const text = source(relative)
    assert.equal(text.includes('preset="content"'), false, relative)
    assert.equal(text.includes("compressImage("), false, relative)
    assert.equal(text.includes("compressScreenshot("), false, relative)
    assert.equal(text.includes("compressContentImage("), false, relative)
    if (kind === "story") {
      assert.match(text, /preset="story"/, relative)
    } else if (kind === "avatar") {
      assert.match(text, /preset="avatar"/, relative)
    } else {
      assert.match(text, new RegExp(`prepareImageForUpload\\("${kind}"`), relative)
    }
  }

  const messages = source("app/(app)/messages/[id]/page.tsx")
  const community = source("app/community/page.tsx")
  assert.match(messages, /preset="avatar"/)
  assert.match(community, /preset="room"/)
  assert.equal(source("lib/avatarUpload.ts").includes("compressImage("), false)
})
