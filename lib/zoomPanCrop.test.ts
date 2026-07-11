import { describe, expect, it } from "vitest"
import {
  clampZoom,
  clampZoomPanOffset,
  computeCoverZoom,
  computeFitScale,
  computeZoomPanDrawRect,
  DEFAULT_ZOOM_PAN_TRANSFORM,
  ZOOM_PAN_MAX,
  ZOOM_PAN_MIN,
} from "./zoomPanCrop"

const FRAME_W = 1200
const FRAME_H = 900

describe("zoomPanCrop", () => {
  it("defaults to fit (zoom 1) with centered offset", () => {
    expect(DEFAULT_ZOOM_PAN_TRANSFORM).toEqual({ zoom: 1, offset: { x: 0, y: 0 } })
    expect(ZOOM_PAN_MIN).toBe(1)
    expect(ZOOM_PAN_MAX).toBe(4)
  })

  it("fits a landscape screenshot entirely inside the frame", () => {
    const rect = computeZoomPanDrawRect(1600, 900, FRAME_W, FRAME_H, 1)
    expect(rect.width).toBe(FRAME_W)
    expect(rect.height).toBeCloseTo(675)
    expect(rect.x).toBeCloseTo(0)
    expect(rect.y).toBeGreaterThan(0)
  })

  it("computes cover zoom so a landscape image fills the frame", () => {
    const zoom = computeCoverZoom(1600, 900, FRAME_W, FRAME_H)
    const rect = computeZoomPanDrawRect(1600, 900, FRAME_W, FRAME_H, zoom)
    expect(rect.width).toBeGreaterThanOrEqual(FRAME_W - 0.5)
    expect(rect.height).toBeGreaterThanOrEqual(FRAME_H - 0.5)
  })

  it("fits a portrait photo entirely inside the frame", () => {
    const rect = computeZoomPanDrawRect(900, 1600, FRAME_W, FRAME_H, 1)
    expect(rect.height).toBe(FRAME_H)
    expect(rect.width).toBeCloseTo(506.25)
    expect(rect.x).toBeGreaterThan(0)
    expect(rect.y).toBeCloseTo(0)
  })

  it("fits a square image entirely inside the frame", () => {
    const rect = computeZoomPanDrawRect(1000, 1000, FRAME_W, FRAME_H, 1)
    expect(rect.width).toBeCloseTo(rect.height)
    expect(rect.width).toBeLessThanOrEqual(FRAME_W)
    expect(rect.height).toBeLessThanOrEqual(FRAME_H)
  })

  it("fits a very tall image entirely inside the frame", () => {
    const rect = computeZoomPanDrawRect(400, 4000, FRAME_W, FRAME_H, 1)
    expect(rect.height).toBe(FRAME_H)
    expect(rect.width).toBeLessThan(FRAME_W)
  })

  it("zooms in from fit and allows panning within bounds", () => {
    const zoom = 2
    const rect = computeZoomPanDrawRect(1600, 900, FRAME_W, FRAME_H, zoom)
    expect(rect.width).toBeGreaterThan(FRAME_W)
    expect(rect.height).toBeGreaterThan(FRAME_H)

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
    expect(clampedRect.x).toBeLessThanOrEqual(0)
    expect(clampedRect.y).toBeLessThanOrEqual(0)
    expect(clampedRect.x).toBeGreaterThanOrEqual(FRAME_W - clampedRect.width)
    expect(clampedRect.y).toBeGreaterThanOrEqual(FRAME_H - clampedRect.height)
  })

  it("ignores pan offset when the image fits inside the frame", () => {
    const offset = clampZoomPanOffset(1600, 900, FRAME_W, FRAME_H, 1, {
      x: 200,
      y: -100,
    })
    expect(offset).toEqual({ x: 0, y: 0 })
  })

  it("clamps zoom between fit and max", () => {
    expect(clampZoom(0.5)).toBe(1)
    expect(clampZoom(10)).toBe(4)
    expect(clampZoom(2.5, 3)).toBe(2.5)
    expect(clampZoom(5, 3)).toBe(3)
  })

  it("computes fit scale as the smaller of width/height ratios", () => {
    expect(computeFitScale(1600, 900, FRAME_W, FRAME_H)).toBeCloseTo(0.75)
    expect(computeFitScale(900, 1600, FRAME_W, FRAME_H)).toBeCloseTo(0.5625)
  })
})
