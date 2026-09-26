import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"
import { fileURLToPath } from "node:url"
import {
  clampContentCoverTransform,
  clampContentZoom,
  CONTENT_FEED_MIN_ASPECT,
  CONTENT_IMAGE_V2_ENCODE_PASSES,
  CONTENT_IMAGE_V2_JPEG_QUALITY,
  CONTENT_IMAGE_V2_MAX_EDGE,
  CONTENT_IMAGE_V2_MIME,
  CONTENT_IMAGE_ASPECTS,
  CONTENT_IMAGE_V2_DEFAULT_ASPECT,
  contentAspectLabel,
  contentCoverLayout,
  contentJpegFileName,
  contentLogicalFrame,
  contentOutputSize,
  contentPresentationAspect,
  imageDecodeErrorMessage,
  orientedPixelSize,
  planContentImageExport,
} from "./contentImageV2.ts"
const HERE = path.dirname(fileURLToPath(import.meta.url))

function assertAspect(width: number, height: number, expected: number, epsilon = 0.02) {
  assert.ok(Math.abs(width / height - expected) < epsilon, `${width}x${height} vs ${expected}`)
}

function assertCovered(
  imageWidth: number,
  imageHeight: number,
  aspect: Parameters<typeof planContentImageExport>[2],
  zoom: number,
  offset: { x: number; y: number }
) {
  const plan = planContentImageExport(imageWidth, imageHeight, aspect, { zoom, offset })
  const { frame, layout, crop, output } = plan
  assert.ok(layout.originX <= 0.01)
  assert.ok(layout.originY <= 0.01)
  assert.ok(layout.originX + layout.displayWidth >= frame.width - 0.01)
  assert.ok(layout.originY + layout.displayHeight >= frame.height - 0.01)
  assert.ok(crop.x >= -0.01)
  assert.ok(crop.y >= -0.01)
  assert.ok(crop.x + crop.width <= imageWidth + 0.5)
  assert.ok(crop.y + crop.height <= imageHeight + 0.5)
  assert.ok(output.scale <= 1)
  assert.ok(Math.max(output.width, output.height) <= CONTENT_IMAGE_V2_MAX_EDGE)
  assert.equal(plan.encodePasses, 1)
  assert.equal(plan.mime, "image/jpeg")
  assert.equal(plan.quality, 0.92)
  return plan
}

describe("content image v2 contract", () => {
  it("offers only 1:1, 4:5, and 16:9, defaulting to 4:5", () => {
    assert.deepEqual(CONTENT_IMAGE_ASPECTS, ["square", "portrait", "landscape"])
    assert.equal(CONTENT_IMAGE_V2_DEFAULT_ASPECT, "portrait")
    assert.equal(contentAspectLabel("square"), "1:1")
    assert.equal(contentAspectLabel("portrait"), "4:5")
    assert.equal(contentAspectLabel("landscape"), "16:9")
    assert.equal(contentPresentationAspect("portrait"), CONTENT_FEED_MIN_ASPECT)
    const modal = fs.readFileSync(path.join(HERE, "../app/components/ImageCropModal.tsx"), "utf8")
    assert.equal(modal.includes("Original"), false)
    assert.equal(modal.includes('"original"'), false)
    assert.match(modal, /CONTENT_IMAGE_V2_DEFAULT_ASPECT/)
  })

  it("exports 1:1, 4:5, and 16:9 from the selected ratio", () => {
    const square = assertCovered(4000, 3000, "square", 1, { x: 0, y: 0 })
    assert.equal(square.output.width, 2560)
    assert.equal(square.output.height, 2560)

    const portrait = assertCovered(4000, 3000, "portrait", 1, { x: 0, y: 0 })
    assertAspect(portrait.output.width, portrait.output.height, 4 / 5)
    assert.equal(Math.max(portrait.output.width, portrait.output.height), 2560)

    const wide = assertCovered(5000, 4000, "landscape", 1, { x: 0, y: 0 })
    assertAspect(wide.output.width, wide.output.height, 16 / 9)
    assert.equal(wide.output.width, 2560)
  })

  it("does not upscale a small source", () => {
    const small = planContentImageExport(400, 500, "portrait")
    assert.equal(small.output.scale, 1)
    assert.equal(small.output.width, 400)
    assert.equal(small.output.height, 500)

    const tinySquare = planContentImageExport(100, 100, "square")
    assert.equal(tinySquare.output.width, 100)
    assert.equal(tinySquare.output.height, 100)
    assert.equal(contentOutputSize(100, 100).scale, 1)
  })

  it("caps a large source at a 2560 longest edge", () => {
    const huge = planContentImageExport(8000, 6000, "landscape")
    assert.ok(Math.max(huge.output.width, huge.output.height) <= 2560)
    assert.equal(huge.output.width, 2560)
    assert.ok(huge.output.scale < 1)
  })

  it("encodes one JPEG at quality 0.92 with a .jpg name", () => {
    const plan = planContentImageExport(1200, 800, "portrait")
    assert.equal(plan.mime, CONTENT_IMAGE_V2_MIME)
    assert.equal(plan.quality, CONTENT_IMAGE_V2_JPEG_QUALITY)
    assert.equal(plan.quality, 0.92)
    assert.equal(plan.encodePasses, CONTENT_IMAGE_V2_ENCODE_PASSES)
    assert.equal(contentJpegFileName("chart.PNG"), "chart.jpg")
    assert.equal(contentJpegFileName("photo.heic"), "photo.jpg")
  })

  it("bakes EXIF orientations that swap pixel axes", () => {
    assert.deepEqual(orientedPixelSize(4032, 3024, 1), { width: 4032, height: 3024 })
    assert.deepEqual(orientedPixelSize(4032, 3024, 6), { width: 3024, height: 4032 })
    assert.deepEqual(orientedPixelSize(4032, 3024, 8), { width: 3024, height: 4032 })
    assert.deepEqual(orientedPixelSize(4032, 3024, 3), { width: 4032, height: 3024 })
    const upright = orientedPixelSize(4032, 3024, 6)
    const plan = planContentImageExport(upright.width, upright.height, "portrait")
    assertAspect(plan.output.width, plan.output.height, 4 / 5)
  })

  it("clamps zoom to 1x–4x and reclamps pan for every ratio", () => {
    assert.equal(clampContentZoom(0.2), 1)
    assert.equal(clampContentZoom(9), 4)
    assert.equal(clampContentZoom(2.5), 2.5)

    for (const aspect of CONTENT_IMAGE_ASPECTS) {
      const plan = assertCovered(4032, 3024, aspect, 2.4, { x: 50_000, y: -80_000 })
      assert.equal(plan.layout.zoom, 2.4)
    }
  })

  it("keeps zoom when the ratio changes and only reclamps pan", () => {
    const before = clampContentCoverTransform(4032, 3024, "landscape", {
      zoom: 2.25,
      offset: { x: 400, y: -120 },
    })
    const after = clampContentCoverTransform(4032, 3024, "portrait", before)
    assert.equal(after.zoom, 2.25)
    const portrait = contentCoverLayout(
      4032,
      3024,
      contentLogicalFrame(contentPresentationAspect("portrait")),
      after
    )
    assert.equal(portrait.zoom, 2.25)
    assert.ok(portrait.originX <= 0)
    assert.ok(portrait.originY <= 0)
  })

  it("does not run a second compression pass", () => {
    const src = fs.readFileSync(path.join(HERE, "renderContentImageV2.ts"), "utf8")
    assert.equal(src.includes("compressImage"), false)
    assert.equal(src.includes("compressScreenshot"), false)
    assert.equal(src.includes("toBlob"), true)
    assert.equal(src.split("toBlob").length - 1, 1)
    assert.match(src, /CONTENT_IMAGE_V2_JPEG_QUALITY/)
  })

  it("keeps the legacy content preset for surfaces that are not migrated", () => {
    const presets = fs.readFileSync(path.join(HERE, "imageCropPresets.ts"), "utf8")
    const aspect = fs.readFileSync(path.join(HERE, "tradeImageAspect.ts"), "utf8")
    const pipeline = fs.readFileSync(path.join(HERE, "contentImagePipeline.ts"), "utf8")
    const preparation = fs.readFileSync(path.join(HERE, "imagePreparation.ts"), "utf8")
    assert.match(aspect, /TRADE_IMAGE_ASPECT = 4 \/ 3/)
    assert.match(aspect, /TRADE_IMAGE_OUTPUT_WIDTH = 1200/)
    assert.match(aspect, /TRADE_IMAGE_OUTPUT_HEIGHT = 900/)
    assert.match(presets, /fillAspect: TRADE_IMAGE_ASPECT/)
    assert.match(presets, /outputWidth: TRADE_IMAGE_OUTPUT_WIDTH/)
    assert.match(pipeline, /CONTENT_IMAGE_CROP_PRESET: ImageCropPresetId = "content"/)
    assert.equal(pipeline.includes("contentV2"), false)
    assert.match(preparation, /contentV2: "ready"/)
    assert.match(preparation, /avatar: "ready"/)
    assert.match(preparation, /story: "ready"/)
    assert.match(preparation, /chat: "ready"/)
    assert.match(preparation, /room: "ready"/)
    assert.match(preparation, /attachment: "ready"/)
  })

  it("explains HEIC when the browser cannot decode it", () => {
    const message = imageDecodeErrorMessage({
      type: "image/heic",
      name: "IMG_2043.HEIC",
    })
    assert.match(message, /HEIC/)
    assert.match(message, /JPEG/)
    assert.doesNotMatch(
      imageDecodeErrorMessage({ type: "image/jpeg", name: "a.jpg" }),
      /HEIC/
    )
  })
})
