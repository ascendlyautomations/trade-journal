import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  clampZoom,
  clampZoomPanOffset,
  computeCoverZoom,
  computeFitScale,
  computeZoomPanDrawRect,
  DEFAULT_ZOOM_PAN_TRANSFORM,
  ZOOM_PAN_MAX,
  ZOOM_PAN_MIN,
} from "./zoomPanCrop.ts"

const FRAME_W = 1200
const FRAME_H = 900

function assertCloseTo(actual: number, expected: number, epsilon = 1e-9) {
  assert.ok(Math.abs(actual - expected) < epsilon)
}

describe("zoomPanCrop", () => {
  it("defaults to fit (zoom 1) with centered offset", () => {
    assert.deepEqual(DEFAULT_ZOOM_PAN_TRANSFORM, { zoom: 1, offset: { x: 0, y: 0 } })
    assert.equal(ZOOM_PAN_MIN, 1)
    assert.equal(ZOOM_PAN_MAX, 4)
  })

  it("fits a landscape screenshot entirely inside the frame", () => {
    const rect = computeZoomPanDrawRect(1600, 900, FRAME_W, FRAME_H, 1)
    assert.equal(rect.width, FRAME_W)
    assertCloseTo(rect.height, 675)
    assertCloseTo(rect.x, 0)
    assert.ok(rect.y > 0)
  })

  it("computes cover zoom so a landscape image fills the frame", () => {
    const zoom = computeCoverZoom(1600, 900, FRAME_W, FRAME_H)
    const rect = computeZoomPanDrawRect(1600, 900, FRAME_W, FRAME_H, zoom)
    assert.ok(rect.width >= FRAME_W - 0.5)
    assert.ok(rect.height >= FRAME_H - 0.5)
  })

  it("fits a portrait photo entirely inside the frame", () => {
    const rect = computeZoomPanDrawRect(900, 1600, FRAME_W, FRAME_H, 1)
    assert.equal(rect.height, FRAME_H)
    assertCloseTo(rect.width, 506.25)
    assert.ok(rect.x > 0)
    assertCloseTo(rect.y, 0)
  })

  it("fits a square image entirely inside the frame", () => {
    const rect = computeZoomPanDrawRect(1000, 1000, FRAME_W, FRAME_H, 1)
    assertCloseTo(rect.width, rect.height)
    assert.ok(rect.width <= FRAME_W)
    assert.ok(rect.height <= FRAME_H)
  })

  it("fits a very tall image entirely inside the frame", () => {
    const rect = computeZoomPanDrawRect(400, 4000, FRAME_W, FRAME_H, 1)
    assert.equal(rect.height, FRAME_H)
    assert.ok(rect.width < FRAME_W)
  })

  it("zooms in from fit and allows panning within bounds", () => {
    const zoom = 2
    const rect = computeZoomPanDrawRect(1600, 900, FRAME_W, FRAME_H, zoom)
    assert.ok(rect.width > FRAME_W)
    assert.ok(rect.height > FRAME_H)

    const clamped = clampZoomPanOffset(1600, 900, FRAME_W, FRAME_H, zoom, {
      x: 500,
      y: -2000,
    })
    const clampedRect = computeZoomPanDrawRect(
      1600,
      900,
      FRAME_W,
      FRAME_H,
      zoom,
      clamped
    )
    assert.ok(clampedRect.x <= 0)
    assert.ok(clampedRect.y <= 0)
    assert.ok(clampedRect.x >= FRAME_W - clampedRect.width)
    assert.ok(clampedRect.y >= FRAME_H - clampedRect.height)
  })

  it("ignores pan offset when the image fits inside the frame", () => {
    const offset = clampZoomPanOffset(1600, 900, FRAME_W, FRAME_H, 1, {
      x: 200,
      y: -100,
    })
    assert.deepEqual(offset, { x: 0, y: 0 })
  })

  it("clamps zoom between fit and max", () => {
    assert.equal(clampZoom(0.5), 1)
    assert.equal(clampZoom(10), 4)
    assert.equal(clampZoom(2.5, 3), 2.5)
    assert.equal(clampZoom(5, 3), 3)
  })

  it("computes fit scale as the smaller of width/height ratios", () => {
    assertCloseTo(computeFitScale(1600, 900, FRAME_W, FRAME_H), 0.75)
    assertCloseTo(computeFitScale(900, 1600, FRAME_W, FRAME_H), 0.5625)
  })
})
