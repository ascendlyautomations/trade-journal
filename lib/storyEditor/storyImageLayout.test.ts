import assert from "node:assert/strict"
import { test } from "node:test"
import { storyImageDrawRect } from "./storyImageLayout.ts"
import {
  clampOverlayScale,
  publishableTextOverlays,
  STORY_RENDER_HEIGHT,
  STORY_RENDER_WIDTH,
} from "./storyTextOverlay.ts"

test("story image layout aspect-fits at unit scale", () => {
  const canvasSize = { width: 360, height: 640 }
  const imageSize = { width: 1200, height: 800 }
  const rect = storyImageDrawRect(
    imageSize,
    canvasSize,
    1,
    { width: 0, height: 0 },
    "contain"
  )
  assert.ok(rect.width <= canvasSize.width)
  assert.ok(rect.height <= canvasSize.height)
  assert.ok(Math.abs(rect.x + rect.width / 2 - canvasSize.width / 2) < 0.5)
  assert.ok(Math.abs(rect.y + rect.height / 2 - canvasSize.height / 2) < 0.5)
})

test("story overlay scale clamps like iOS editor", () => {
  assert.equal(clampOverlayScale(10), 3)
  assert.equal(clampOverlayScale(0.01), 0.5)
})

test("publishable overlays drop blank text", () => {
  const kept = publishableTextOverlays([
    {
      id: "1",
      text: "Hi",
      normalizedCenter: { x: 0.5, y: 0.5 },
      scale: 1,
      rotationRadians: 0,
      textFill: { red: 1, green: 1, blue: 1, alpha: 1 },
      alignment: "center",
      showsBackground: false,
    },
    {
      id: "2",
      text: "   ",
      normalizedCenter: { x: 0.5, y: 0.5 },
      scale: 1,
      rotationRadians: 0,
      textFill: { red: 1, green: 1, blue: 1, alpha: 1 },
      alignment: "center",
      showsBackground: false,
    },
  ])
  assert.equal(kept.length, 1)
  assert.equal(kept[0]?.text, "Hi")
})

test("cover base fill exceeds canvas on one axis", () => {
  const canvasSize = { width: 360, height: 640 }
  const imageSize = { width: 1200, height: 800 }
  const rect = storyImageDrawRect(
    imageSize,
    canvasSize,
    1,
    { width: 0, height: 0 },
    "cover"
  )
  assert.ok(rect.width >= canvasSize.width - 0.5)
  assert.ok(rect.height >= canvasSize.height - 0.5)
})

test("story render pixel size matches iOS", () => {
  assert.equal(STORY_RENDER_WIDTH, 1080)
  assert.equal(STORY_RENDER_HEIGHT, 1920)
})
