import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  anchoredMenuPlacement,
  keyboardHeightFromViewport,
} from "./mobileWebKeyboard.ts"

describe("keyboardHeightFromViewport", () => {
  it("ignores toolbar-sized viewport changes", () => {
    assert.equal(
      keyboardHeightFromViewport({
        innerHeight: 844,
        visualHeight: 780,
        visualOffsetTop: 0,
      }),
      0
    )
  })

  it("reports a keyboard that covers the bottom of the layout viewport", () => {
    assert.equal(
      keyboardHeightFromViewport({
        innerHeight: 844,
        visualHeight: 500,
        visualOffsetTop: 0,
      }),
      344
    )
  })
})

describe("anchoredMenuPlacement", () => {
  it("opens below the trigger when there is room", () => {
    const placed = anchoredMenuPlacement({
      triggerTop: 120,
      triggerBottom: 164,
      triggerLeft: 16,
      triggerWidth: 200,
      viewTop: 0,
      viewBottom: 700,
      viewLeft: 0,
      viewRight: 390,
      preferredMaxHeight: 240,
      minUsableBelow: 72,
    })
    assert.equal(placed.top, 168)
    assert.equal(placed.maxHeight, 240)
    assert.equal(placed.left, 16)
  })

  it("flips above the trigger when the keyboard leaves no room below", () => {
    const placed = anchoredMenuPlacement({
      triggerTop: 420,
      triggerBottom: 464,
      triggerLeft: 16,
      triggerWidth: 180,
      viewTop: 0,
      viewBottom: 500,
      viewLeft: 0,
      viewRight: 390,
      preferredMaxHeight: 280,
      minUsableBelow: 120,
      minWidth: 260,
    })
    assert.ok(placed.top < 420)
    assert.ok(placed.top + placed.maxHeight <= 420)
    assert.equal(placed.width, 260)
  })
})
