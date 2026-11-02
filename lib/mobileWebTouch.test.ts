import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  shouldDismissKeyboardOnTouchMove,
  shouldDismissSheetFromVerticalDrag,
} from "./mobileWebTouch.ts"

describe("shouldDismissSheetFromVerticalDrag", () => {
  it("dismisses a downward header drag", () => {
    assert.equal(shouldDismissSheetFromVerticalDrag(40, 100, 48, 180), true)
  })

  it("ignores a short tap and a horizontal swipe", () => {
    assert.equal(shouldDismissSheetFromVerticalDrag(40, 100, 42, 130), false)
    assert.equal(shouldDismissSheetFromVerticalDrag(20, 100, 160, 180), false)
  })
})

describe("shouldDismissKeyboardOnTouchMove", () => {
  it("blurs a focused field when the drag starts elsewhere", () => {
    assert.equal(
      shouldDismissKeyboardOnTouchMove({
        startedOnField: false,
        deltaY: 20,
        activeTag: "TEXTAREA",
      }),
      true
    )
  })

  it("keeps the caret when the drag starts on the field", () => {
    assert.equal(
      shouldDismissKeyboardOnTouchMove({
        startedOnField: true,
        deltaY: 40,
        activeTag: "INPUT",
      }),
      false
    )
    assert.equal(
      shouldDismissKeyboardOnTouchMove({
        startedOnField: false,
        deltaY: 4,
        activeTag: "INPUT",
      }),
      false
    )
    assert.equal(
      shouldDismissKeyboardOnTouchMove({
        startedOnField: false,
        deltaY: 20,
        activeTag: "BUTTON",
      }),
      false
    )
  })
})
