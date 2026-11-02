import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { nextDialogFocusIndex } from "./mobileWebA11y.ts"

describe("nextDialogFocusIndex", () => {
  it("wraps forward and backward", () => {
    assert.equal(nextDialogFocusIndex(0, 3, false), 1)
    assert.equal(nextDialogFocusIndex(2, 3, false), 0)
    assert.equal(nextDialogFocusIndex(0, 3, true), 2)
    assert.equal(nextDialogFocusIndex(1, 3, true), 0)
  })

  it("stays put when the dialog has one control", () => {
    assert.equal(nextDialogFocusIndex(0, 1, false), 0)
    assert.equal(nextDialogFocusIndex(-1, 4, false), 0)
  })
})
