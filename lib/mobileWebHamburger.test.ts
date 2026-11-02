import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { resolveMobileWebHamburgerSection } from "./mobileWebHamburger.ts"

describe("resolveMobileWebHamburgerSection", () => {
  it("maps create destinations to the Create accordion", () => {
    assert.equal(resolveMobileWebHamburgerSection("/app"), "create")
    assert.equal(resolveMobileWebHamburgerSection("/create/post"), "create")
    assert.equal(resolveMobileWebHamburgerSection("/create/clip"), "create")
    assert.equal(resolveMobileWebHamburgerSection("/create/story"), "create")
  })

  it("maps desktop Analytics destinations", () => {
    assert.equal(resolveMobileWebHamburgerSection("/calendar"), "analytics")
    assert.equal(resolveMobileWebHamburgerSection("/analytics/propfirm"), "analytics")
    assert.equal(resolveMobileWebHamburgerSection("/analyst"), "analytics")
    assert.equal(resolveMobileWebHamburgerSection("/achievements"), "analytics")
    assert.equal(resolveMobileWebHamburgerSection("/backtest"), "analytics")
    assert.equal(resolveMobileWebHamburgerSection("/streaks"), "analytics")
  })

  it("maps desktop Community destinations and room paths", () => {
    assert.equal(resolveMobileWebHamburgerSection("/community"), "community")
    assert.equal(resolveMobileWebHamburgerSection("/leaderboard"), "community")
    assert.equal(resolveMobileWebHamburgerSection("/explore"), "community")
    assert.equal(resolveMobileWebHamburgerSection("/room/abc"), "community")
  })

  it("maps account and support destinations", () => {
    assert.equal(resolveMobileWebHamburgerSection("/settings"), "account")
    assert.equal(resolveMobileWebHamburgerSection("/notifications"), "account")
    assert.equal(resolveMobileWebHamburgerSection("/referrals"), "account")
    assert.equal(resolveMobileWebHamburgerSection("/affiliate"), "account")
    assert.equal(resolveMobileWebHamburgerSection("/help"), "support")
    assert.equal(resolveMobileWebHamburgerSection("/privacy"), "support")
    assert.equal(resolveMobileWebHamburgerSection("/terms"), "support")
    assert.equal(resolveMobileWebHamburgerSection("/feature-requests"), "support")
  })

  it("leaves desktop primary destinations unsectioned", () => {
    assert.equal(resolveMobileWebHamburgerSection("/dashboard"), null)
    assert.equal(resolveMobileWebHamburgerSection("/trades"), null)
    assert.equal(resolveMobileWebHamburgerSection("/feed"), null)
    assert.equal(resolveMobileWebHamburgerSection("/profile/ada"), null)
    assert.equal(resolveMobileWebHamburgerSection("/messages"), null)
    assert.equal(resolveMobileWebHamburgerSection("/admin"), null)
    assert.equal(resolveMobileWebHamburgerSection("/import"), null)
  })
})
