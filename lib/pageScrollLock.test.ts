import { beforeEach, describe, it } from "node:test"
import assert from "node:assert/strict"
import {
  lockPageScroll,
  resetPageScrollLock,
  unlockPageScroll,
} from "./pageScrollLock.ts"

type OverflowElement = {
  style: {
    overflow: string
    position: string
    top: string
    left: string
    right: string
    width: string
  }
  classList?: { contains: (name: string) => boolean }
  scrollTop?: number
}

function createOverflowElement(): OverflowElement {
  return {
    style: { overflow: "", position: "", top: "", left: "", right: "", width: "" },
  }
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

  it("pins the body on phone web and restores scroll when the sheet closes", () => {
    html.classList = { contains: () => false }
    let scrolled = { x: -1, y: -1 }
    Object.defineProperty(globalThis, "window", {
      configurable: true,
      value: {
        scrollY: 240,
        matchMedia: () => ({ matches: true }),
        scrollTo: (x: number, y: number) => {
          scrolled = { x, y }
        },
      },
    })

    lockPageScroll()
    assert.equal(body.style.position, "fixed")
    assert.equal(body.style.top, "-240px")
    assert.equal(html.style.overflow, "hidden")

    unlockPageScroll()
    assert.equal(body.style.position, "")
    assert.equal(body.style.top, "")
    assert.equal(html.style.overflow, "")
    assert.deepEqual(scrolled, { x: 0, y: 240 })
  })

  it("does not pin the body on native iOS or desktop widths", () => {
    html.classList = { contains: (name) => name === "tt-native-ios" }
    Object.defineProperty(globalThis, "window", {
      configurable: true,
      value: {
        scrollY: 80,
        matchMedia: () => ({ matches: true }),
        scrollTo: () => {},
      },
    })

    lockPageScroll()
    assert.equal(body.style.position, "")
    assert.equal(body.style.overflow, "hidden")
    unlockPageScroll()

    html.classList = { contains: () => false }
    Object.defineProperty(globalThis, "window", {
      configurable: true,
      value: {
        scrollY: 80,
        matchMedia: () => ({ matches: false }),
        scrollTo: () => {},
      },
    })
    lockPageScroll()
    assert.equal(body.style.position, "")
    unlockPageScroll()
  })
})
export {}
