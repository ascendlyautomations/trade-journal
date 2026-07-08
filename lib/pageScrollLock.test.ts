const assert = require("node:assert/strict")
const { beforeEach, describe, it } = require("node:test")

function createOverflowElement() {
  return { style: { overflow: "" } }
}

describe("page scroll lock", () => {
  let html
  let body

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

    const { resetPageScrollLock } = require("./pageScrollLock.ts")
    resetPageScrollLock()
    html.style.overflow = ""
    body.style.overflow = ""
  })

  it("locks and unlocks the page once", () => {
    const { lockPageScroll, unlockPageScroll } = require("./pageScrollLock.ts")

    lockPageScroll()
    assert.equal(html.style.overflow, "hidden")
    assert.equal(body.style.overflow, "hidden")

    unlockPageScroll()
    assert.equal(html.style.overflow, "")
    assert.equal(body.style.overflow, "")
  })

  it("keeps the page locked until the final modal closes", () => {
    const { lockPageScroll, unlockPageScroll } = require("./pageScrollLock.ts")

    lockPageScroll()
    lockPageScroll()

    unlockPageScroll()
    assert.equal(body.style.overflow, "hidden")

    unlockPageScroll()
    assert.equal(body.style.overflow, "")
  })

  it("restores the original overflow values", () => {
    const { lockPageScroll, unlockPageScroll } = require("./pageScrollLock.ts")

    html.style.overflow = "scroll"
    body.style.overflow = "auto"

    lockPageScroll()
    unlockPageScroll()

    assert.equal(html.style.overflow, "scroll")
    assert.equal(body.style.overflow, "auto")
  })

  it("force-resets stale locks on navigation", () => {
    const {
      lockPageScroll,
      resetPageScrollLock,
      unlockPageScroll,
    } = require("./pageScrollLock.ts")

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
