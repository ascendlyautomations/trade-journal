import { beforeEach, describe, it } from "node:test"
import assert from "node:assert/strict"
import {
  lockPageScroll,
  resetPageScrollLock,
  unlockPageScroll,
} from "./pageScrollLock.ts"

type OverflowElement = { style: { overflow: string } }

function createOverflowElement(): OverflowElement {
  return { style: { overflow: "" } }
}

describe("page scroll lock", () => {
  let html: OverflowElement
  let body: OverflowElement

  beforeEach(() => {
    html = createOverflowElement()
    body = createOverflowElement()
    Object.defineProperty(globalThis, "document", {
      configurable: true,
      value: {
        documentElement: html,
        body,
      },
    })

    resetPageScrollLock()
    html.style.overflow = ""
    body.style.overflow = ""
  })

  it("locks and unlocks the page once", () => {
    lockPageScroll()
    assert.equal(html.style.overflow, "hidden")
    assert.equal(body.style.overflow, "hidden")

    unlockPageScroll()
    assert.equal(html.style.overflow, "")
    assert.equal(body.style.overflow, "")
  })

  it("keeps the page locked until the final modal closes", () => {
    lockPageScroll()
    lockPageScroll()

    unlockPageScroll()
    assert.equal(body.style.overflow, "hidden")

    unlockPageScroll()
    assert.equal(body.style.overflow, "")
  })

  it("restores the original overflow values", () => {
    html.style.overflow = "scroll"
    body.style.overflow = "auto"

    lockPageScroll()
    unlockPageScroll()

    assert.equal(html.style.overflow, "scroll")
    assert.equal(body.style.overflow, "auto")
  })

  it("force-resets stale locks on navigation", () => {
    lockPageScroll()
    lockPageScroll()
    resetPageScrollLock()

    assert.equal(html.style.overflow, "")
    assert.equal(body.style.overflow, "")

    lockPageScroll()
    unlockPageScroll()
    assert.equal(body.style.overflow, "")
  })
})
export {}
