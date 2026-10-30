import { describe, it } from "node:test"
import assert from "node:assert/strict"
import {
  LEADING_BACK_ZONE_WIDTH_RATIO,
  isLeadingBackGestureZone,
  leadingBackZoneMaxX,
} from "./leadingBackGestureZone.ts"

describe("leadingBackGestureZone", () => {
  it("uses a 10% leading band", () => {
    assert.equal(LEADING_BACK_ZONE_WIDTH_RATIO, 0.1)
    assert.equal(leadingBackZoneMaxX(400), 40)
  })

  it("classifies touch x against viewport width", () => {
    assert.equal(isLeadingBackGestureZone(39, 400), true)
    assert.equal(isLeadingBackGestureZone(41, 400), false)
  })
})

export {}
