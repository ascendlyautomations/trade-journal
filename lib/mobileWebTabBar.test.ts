import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  resolveMobileWebActiveTab,
  resolveMobileWebPageHeader,
  shouldMountMobileWebTabBar,
} from "./mobileWebTabBar.ts"

describe("resolveMobileWebActiveTab", () => {
  it("maps the five tab roots", () => {
    assert.equal(resolveMobileWebActiveTab("/dashboard", "/profile/ada"), "home")
    assert.equal(resolveMobileWebActiveTab("/feed", "/profile/ada"), "feed")
    assert.equal(resolveMobileWebActiveTab("/messages/abc", "/profile/ada"), "messages")
    assert.equal(resolveMobileWebActiveTab("/profile/ada", "/profile/ada"), "profile")
    assert.equal(resolveMobileWebActiveTab("/create/post", "/profile/ada"), "create")
    assert.equal(resolveMobileWebActiveTab("/app", "/profile/ada"), "create")
  })

  it("treats an open create sheet as the Create tab", () => {
    assert.equal(
      resolveMobileWebActiveTab("/feed", "/profile/ada", true),
      "create"
    )
  })

  it("leaves secondary destinations unselected", () => {
    assert.equal(resolveMobileWebActiveTab("/calendar", "/profile/ada"), null)
    assert.equal(resolveMobileWebActiveTab("/trades", "/profile/ada"), null)
    assert.equal(resolveMobileWebActiveTab("/explore", "/profile/ada"), null)
    assert.equal(resolveMobileWebActiveTab("/settings", "/profile/ada"), null)
  })
})

describe("shouldMountMobileWebTabBar", () => {
  it("is off on marketing home and signed-out sessions", () => {
    assert.equal(shouldMountMobileWebTabBar("/dashboard", false), false)
    assert.equal(shouldMountMobileWebTabBar("/", true), false)
    assert.equal(shouldMountMobileWebTabBar("/feed", true), true)
  })
})

describe("resolveMobileWebPageHeader", () => {
  it("uses native-style titles for secondary phone pages", () => {
    assert.deepEqual(resolveMobileWebPageHeader("/calendar"), {
      title: "Calendar",
      backHref: "/dashboard",
    })
    assert.deepEqual(resolveMobileWebPageHeader("/explore"), {
      title: "Explore",
      backHref: "/feed",
    })
    assert.equal(resolveMobileWebPageHeader("/dashboard"), null)
    assert.equal(resolveMobileWebPageHeader("/feed"), null)
  })
})
