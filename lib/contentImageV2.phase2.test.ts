import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import test from "node:test"
import { fileURLToPath } from "node:url"
import {
  CONTENT_IMAGE_V2_MAX_EDGE,
  CONTENT_IMAGE_V2_MIME,
  CONTENT_IMAGE_V2_PRESET,
  contentJpegFileName,
  planContentImageExport,
} from "./contentImageV2.ts"
import { resolveContentUploadFile } from "./contentImagePipeline.ts"

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")

function source(relative: string): string {
  return fs.readFileSync(path.join(ROOT, relative), "utf8")
}

test("prepared content files skip the second compression pass", async () => {
  const prepared = new File(["jpeg"], "chart.jpg", { type: "image/jpeg" })
  let compressions = 0
  const uploaded = await resolveContentUploadFile(prepared, true, async (file) => {
    compressions += 1
    return file
  })
  assert.equal(compressions, 0)
  assert.equal(uploaded, prepared)
  assert.equal(uploaded.type, CONTENT_IMAGE_V2_MIME)
  assert.equal(uploaded.name.endsWith(".jpg"), true)
})

test("unprepared images still use the legacy compression callback", async () => {
  const raw = new File(["png"], "shot.png", { type: "image/png" })
  const uploaded = await resolveContentUploadFile(raw, false, async (file) => {
    return new File(["webp"], "shot.webp", { type: "image/webp" })
  })
  assert.equal(uploaded.type, "image/webp")
  assert.equal(uploaded.name.endsWith(".webp"), true)
  assert.notEqual(uploaded, raw)
})

test("jpeg filename matches the jpeg MIME", () => {
  assert.equal(contentJpegFileName("Chart.PNG"), "Chart.jpg")
  assert.equal(contentJpegFileName("photo.heic"), "photo.jpg")
  assert.equal(CONTENT_IMAGE_V2_PRESET, "contentV2")
})

test("ratios stay within 2560 and do not upscale a small image", () => {
  for (const aspect of ["square", "portrait", "landscape"] as const) {
    const large = planContentImageExport(4000, 3000, aspect, {
      zoom: 1,
      offset: { x: 0, y: 0 },
    })
    assert.ok(large.output.width <= CONTENT_IMAGE_V2_MAX_EDGE)
    assert.ok(large.output.height <= CONTENT_IMAGE_V2_MAX_EDGE)
    assert.equal(Math.max(large.output.width, large.output.height) <= 2560, true)

    const small = planContentImageExport(640, 480, aspect, {
      zoom: 1,
      offset: { x: 0, y: 0 },
    })
    assert.ok(small.output.width <= 640)
    assert.ok(small.output.height <= 480)
    assert.equal(small.output.scale, 1)
  }
})

test("trade, post, and achievement uploads use content V2 without a second encode", () => {
  const tradeForm = source("app/components/InputTradeForm.tsx")
  const quickTrade = source("app/components/QuickTradeModal.tsx")
  const tradeHook = source("lib/useTradeImageCropUpload.ts")
  const saveTrade = source("lib/saveManualTrade.ts")
  const post = source("app/profile/[id]/page.tsx")
  const achievement = source("app/components/AchievementUploadModal.tsx")

  for (const [name, text] of [
    ["InputTradeForm", tradeForm],
    ["QuickTradeModal", quickTrade],
    ["useTradeImageCropUpload", tradeHook],
    ["profile post", post],
    ["AchievementUploadModal", achievement],
  ] as const) {
    assert.equal(text.includes("CONTENT_IMAGE_V2_PRESET"), true, name)
    assert.equal(text.includes("compressImage("), false, name)
    assert.equal(text.includes("compressScreenshot("), false, name)
    assert.equal(text.includes("compressContentImage("), false, name)
  }

  assert.equal(tradeForm.includes("prepared: true"), true)
  assert.equal(saveTrade.includes("prepared: true"), true)
  assert.match(tradeForm, /if \(image\) \{[\s\S]*prepared: true/)
  assert.match(tradeForm, /screenshotUrl \?\? prevImg/)
  assert.match(tradeForm, /image_display_mode: screenshotDisplayMode/)
  assert.equal(tradeForm.includes("image_crop"), false)
  assert.equal(achievement.includes("image_crop"), false)
  assert.match(post, /bucket: "profile_posts"/)
  assert.match(achievement, /achievements\/\$\{userId\}/)
  assert.match(achievement, /bucket: "screenshots"/)
})

test("crop cancel does not hand a file to the upload callback", () => {
  const hook = source("lib/useImageCropUpload.ts")
  const cancel = hook.slice(hook.indexOf("const handleCropCancel"))
  const save = cancel.indexOf("const handleCropSave")
  assert.equal(cancel.slice(0, save).includes("onCropped"), false)
  assert.match(hook, /onCropped\(file\)/)
})

test("replacing the source resets crop aspect and revokes the previous preview", () => {
  const modal = source("app/components/ImageCropModal.tsx")
  assert.match(modal, /CONTENT_IMAGE_V2_DEFAULT_ASPECT/)
  assert.equal(modal.includes('setContentAspect("original")'), false)
  assert.match(modal, /URL\.revokeObjectURL\(url\)/)
  assert.match(modal, /\}, \[open, file\]\)/)
})

test("upload failure still returns an error instead of a path", () => {
  const pipeline = source("lib/contentImagePipeline.ts")
  assert.match(pipeline, /if \(upErr\)/)
  assert.match(pipeline, /path: null/)
  const tradeForm = source("app/components/InputTradeForm.tsx")
  assert.match(tradeForm, /if \(uploaded\.error\)/)
})

test("legacy content preset constant remains for the old crop helper", () => {
  const pipeline = source("lib/contentImagePipeline.ts")
  assert.match(pipeline, /CONTENT_IMAGE_CROP_PRESET: ImageCropPresetId = "content"/)
})
